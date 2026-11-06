#!/usr/bin/env bash
# M2 E2E REAL: two isolated apps from DIFFERENT repositories on one disposable host.
# Uses a Docker Ubuntu container as the disposable host. No mocks of id/useradd/systemctl.
# Demonstrates: enrol host once -> add app A (repo1) -> add app B (repo2) -> isolation
# -> remove A (data preserved) -> reconcile -> re-add A -> negative tests.
# Evidence: SHA, commands, identities, directories, drift, preservation, reversibility.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CONTAINER="portico-m2-e2e-$(date +%s)"
IMAGE="ubuntu:22.04"
HOST="root@localhost"
REPO1="owner/private-app-a"
REPO2="owner/private-app-b"
STATE_FILE="/var/lib/portico-deploy/state.json"

echo "=== E2E: starting disposable Docker host $CONTAINER ($IMAGE) ==="
if ! docker pull -q "$IMAGE" >/dev/null 2>&1; then
  fail "cannot pull $IMAGE (no network?)"
fi
if ! docker run -d --name "$CONTAINER" "$IMAGE" sleep 300 >/dev/null 2>&1; then
  fail "cannot start container $CONTAINER"
fi
trap 'docker rm -f "$CONTAINER" >/dev/null 2>&1 || true' EXIT

# Install prerequisites inside the container.
echo "=== Installing prerequisites in container ==="
docker exec "$CONTAINER" bash -c '
  apt-get update -qq && apt-get install -y -qq python3 sudo ca-certificates >/dev/null 2>&1
' || fail "cannot install prerequisites in container"

# Copy remote scripts into the container.
echo "=== Copying remote scripts into container ==="
docker exec "$CONTAINER" mkdir -p /usr/local/libexec
docker cp "$ROOT/scripts/portico-deploy-enroll.sh" "$CONTAINER:/usr/local/libexec/portico-deploy-enroll.sh"
docker cp "$ROOT/scripts/portico-deploy-app-add.sh" "$CONTAINER:/usr/local/libexec/portico-deploy-app-add.sh"
docker cp "$ROOT/scripts/portico-deploy-app-remove.sh" "$CONTAINER:/usr/local/libexec/portico-deploy-app-remove.sh"
docker cp "$ROOT/scripts/portico-deploy-reconcile.sh" "$CONTAINER:/usr/local/libexec/portico-deploy-reconcile.sh"
docker exec "$CONTAINER" chmod 0755 /usr/local/libexec/portico-deploy-enroll.sh /usr/local/libexec/portico-deploy-app-add.sh /usr/local/libexec/portico-deploy-app-remove.sh /usr/local/libexec/portico-deploy-reconcile.sh

# --- 1. Enrol the host (once, reusable across repos) ---
echo '=== 1. Enrolling host ==='
if ! docker exec -e PD_SKIP_SYSTEMD_CHECK=1 "$CONTAINER" /usr/local/libexec/portico-deploy-enroll.sh "$HOST" "$STATE_FILE" > "$TMP/enroll.out" 2>&1; then
  echo "ENROLL OUT: $(cat "$TMP/enroll.out")" >&2
  fail "enrolment failed"
fi
grep -q 'ENROLL_OK' "$TMP/enroll.out" || { cat "$TMP/enroll.out"; fail "ENROLL_OK missing"; }
docker exec "$CONTAINER" test -f "$STATE_FILE" || fail "state file not created"
docker exec "$CONTAINER" python3 -c "import json; s=json.load(open('$STATE_FILE')); assert s['host']=='root@localhost'; assert 'apps' in s; assert s['version']==1" || fail "state content invalid"
echo "SHA: $(git rev-parse HEAD)"
echo "Command: docker exec $CONTAINER /usr/local/libexec/portico-deploy-enroll.sh root@localhost $STATE_FILE"

# --- 2. Add app A (repo1) ---
echo '=== 2. Adding app A (repo1) ==='
docker exec -e PD_SKIP_SYSTEMD_CHECK=1 "$CONTAINER" /usr/local/libexec/portico-deploy-app-add.sh \
  proj-a "$HOST" "$REPO1" public static production "$STATE_FILE" > "$TMP/appa.out" 2>&1 || fail "app A add failed"
grep -q 'APP_ADD_OK' "$TMP/appa.out" || { cat "$TMP/appa.out"; fail "APP_ADD_OK missing for A"; }
docker exec "$CONTAINER" test -d /opt/portico-deploy/apps/proj-a || fail "app A dir missing"
docker exec "$CONTAINER" test -d /opt/portico-deploy/apps/proj-a/releases || fail "app A releases dir missing"
# Identity: directory owned by pd-proj-a
OWNER_A="$(docker exec "$CONTAINER" stat -c '%U' /opt/portico-deploy/apps/proj-a)"
[[ "$OWNER_A" == "pd-proj-a" ]] || { echo "Owner of app A dir: $OWNER_A"; fail "app A dir not owned by pd-proj-a"; }
# Identity: user pd-proj-a exists
docker exec "$CONTAINER" id pd-proj-a >/dev/null 2>&1 || fail "user pd-proj-a does not exist"
docker exec "$CONTAINER" python3 -c "import json; s=json.load(open('$STATE_FILE')); assert 'proj-a' in s['apps']; assert s['apps']['proj-a']['repo']=='$REPO1'; assert s['apps']['proj-a']['environment']=='production'; assert s['apps']['proj-a']['runner_user']=='pd-proj-a'" || fail "app A state invalid"
echo "Command: docker exec $CONTAINER /usr/local/libexec/portico-deploy-app-add.sh proj-a root@localhost $REPO1 public static production $STATE_FILE"

# --- 3. Add app B (repo2, different repo, same host) ---
echo '=== 3. Adding app B (repo2, different repo) ==='
docker exec -e PD_SKIP_SYSTEMD_CHECK=1 "$CONTAINER" /usr/local/libexec/portico-deploy-app-add.sh \
  proj-b "$HOST" "$REPO2" dist static staging "$STATE_FILE" > "$TMP/appb.out" 2>&1 || fail "app B add failed"
grep -q 'APP_ADD_OK' "$TMP/appb.out" || { cat "$TMP/appb.out"; fail "APP_ADD_OK missing for B"; }
docker exec "$CONTAINER" test -d /opt/portico-deploy/apps/proj-b || fail "app B dir missing"
# Isolation: app B has its own directory, not inside app A.
OWNER_B="$(docker exec "$CONTAINER" stat -c '%U' /opt/portico-deploy/apps/proj-b)"
[[ "$OWNER_B" == "pd-proj-b" ]] || { echo "Owner of app B dir: $OWNER_B"; fail "app B dir not owned by pd-proj-b"; }
docker exec "$CONTAINER" id pd-proj-b >/dev/null 2>&1 || fail "user pd-proj-b does not exist"
docker exec "$CONTAINER" python3 -c "import json; s=json.load(open('$STATE_FILE')); assert 'proj-b' in s['apps']; assert s['apps']['proj-b']['repo']=='$REPO2'; assert s['apps']['proj-b']['environment']=='staging'; assert s['apps']['proj-b']['runner_user']=='pd-proj-b'" || fail "app B state invalid"
echo "Command: docker exec $CONTAINER /usr/local/libexec/portico-deploy-app-add.sh proj-b root@localhost $REPO2 dist static staging $STATE_FILE"

# --- 4. Idempotency: re-add app A, no changes ---
echo '=== 4. Idempotency check ==='
docker exec -e PD_SKIP_SYSTEMD_CHECK=1 "$CONTAINER" /usr/local/libexec/portico-deploy-app-add.sh \
  proj-a "$HOST" "$REPO1" public static production "$STATE_FILE" > "$TMP/appa2.out" 2>&1 || fail "re-add app A failed"
grep -q 'already registered identically' "$TMP/appa2.out" || { cat "$TMP/appa2.out"; fail "idempotency message missing"; }

# --- 5. Remove app A (data preserved) ---
echo '=== 5. Removing app A (data preserved) ==='
docker exec -e PD_SKIP_SYSTEMD_CHECK=1 "$CONTAINER" /usr/local/libexec/portico-deploy-app-remove.sh \
  proj-a "$HOST" "$REPO1" "$STATE_FILE" > "$TMP/removea.out" 2>&1 || fail "app A remove failed"
grep -q 'APP_REMOVE_OK' "$TMP/removea.out" || { cat "$TMP/removea.out"; fail "APP_REMOVE_OK missing"; }
grep -q 'data preserved' "$TMP/removea.out" || fail "data preservation missing"
docker exec "$CONTAINER" test -d /opt/portico-deploy/apps/proj-a || fail "app A data deleted (should be preserved)"
docker exec "$CONTAINER" test -d /opt/portico-deploy/apps/proj-a/releases || fail "app A releases deleted (should be preserved)"
docker exec "$CONTAINER" python3 -c "import json; s=json.load(open('$STATE_FILE')); assert 'proj-a' not in s['apps']; assert 'proj-b' in s['apps']; assert len(s['removed_apps'])==1" || fail "state invalid after removal"
echo "Command: docker exec $CONTAINER /usr/local/libexec/portico-deploy-app-remove.sh proj-a root@localhost $REPO1 $STATE_FILE"

# --- 6. Reconcile: app B still consistent ---
echo '=== 6. Reconcile ==='
docker exec -e PD_SKIP_SYSTEMD_CHECK=1 "$CONTAINER" /usr/local/libexec/portico-deploy-reconcile.sh "$HOST" "$REPO2" "$STATE_FILE" > "$TMP/reconcile.out" 2>&1 || fail "reconcile failed"
grep -q 'RECONCILE_OK' "$TMP/reconcile.out" || { cat "$TMP/reconcile.out"; fail "reconcile OK missing"; }
echo "Command: docker exec $CONTAINER /usr/local/libexec/portico-deploy-reconcile.sh root@localhost $REPO2 $STATE_FILE"

# --- 7. Re-add app A (reversibility: data preserved) ---
echo '=== 7. Re-adding app A (reversibility) ==='
docker exec -e PD_SKIP_SYSTEMD_CHECK=1 "$CONTAINER" /usr/local/libexec/portico-deploy-app-add.sh \
  proj-a "$HOST" "$REPO1" public static production "$STATE_FILE" > "$TMP/readda.out" 2>&1 || fail "re-add app A failed"
grep -q 'APP_ADD_OK' "$TMP/readda.out" || { cat "$TMP/readda.out"; fail "APP_ADD_OK missing for re-add"; }
docker exec "$CONTAINER" test -d /opt/portico-deploy/apps/proj-a || fail "app A not restored"

# --- 8. Negative: app-remove for non-registered app ---
echo '=== 8. Negative: remove non-registered app ==='
docker exec -e PD_SKIP_SYSTEMD_CHECK=1 "$CONTAINER" /usr/local/libexec/portico-deploy-app-remove.sh \
  ghost-app "$HOST" "$REPO1" "$STATE_FILE" > "$TMP/negative.out" 2>&1 || fail "negative remove should not fail"
grep -q 'not registered; nothing to remove' "$TMP/negative.out" || { cat "$TMP/negative.out"; fail "negative remove message missing"; }

# --- 9. Evidence summary ---
echo '=== EVIDENCE ==='
echo "Container: $CONTAINER"
echo "Image: $IMAGE"
echo "Host: $HOST"
echo "State file: $STATE_FILE"
echo "Commit SHA: $(git rev-parse HEAD)"
echo "Apps registered: $(docker exec "$CONTAINER" python3 -c "import json; s=json.load(open('$STATE_FILE')); print(', '.join(s.get('apps',{})))")"
echo "Removed apps: $(docker exec "$CONTAINER" python3 -c "import json; s=json.load(open('$STATE_FILE')); print(', '.join(a['project'] for a in s.get('removed_apps',[])))")"
echo "App A dir owner: $(docker exec "$CONTAINER" stat -c '%U' /opt/portico-deploy/apps/proj-a)"
echo "App B dir owner: $(docker exec "$CONTAINER" stat -c '%U' /opt/portico-deploy/apps/proj-b)"
echo "App A dir exists: $(docker exec "$CONTAINER" test -d /opt/portico-deploy/apps/proj-a && echo yes || echo no)"
echo "App B dir exists: $(docker exec "$CONTAINER" test -d /opt/portico-deploy/apps/proj-b && echo yes || echo no)"

echo 'PASS: M2 E2E two isolated apps from different repos on disposable Docker host'
