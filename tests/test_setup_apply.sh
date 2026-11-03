#!/usr/bin/env bash
# Check no host mutation is permitted without protected main.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1 ${2:-}" == "auth status" ]]; then exit 0; fi
if [[ "$1 ${2:-}" == "repo view" ]]; then
    if [[ " $* " == *" defaultBranchRef "* ]]; then
        echo "${GH_TEST_BRANCH:-main}"
    else
        echo true
    fi
    exit 0
fi
if [[ "$1 ${2:-}" == "api repos/example/private-site/branches/main/protection" ]]; then
    exit 1
fi
echo "Unexpected GitHub API call: $*" >&2
exit 1
MOCK
cat > "$TMP/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
echo touched > "${SSH_MARKER:?}"
exit 1
MOCK
chmod +x "$TMP/bin/"*
export SSH_MARKER="$TMP/ssh.called"
if printf '%s\n' demo-site | PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo example/private-site --project demo-site --host admin@server --apply > "$TMP/out" 2>&1; then
    echo 'FAIL: accepted unprotected main' >&2; exit 1
fi
grep -q 'branch protection' "$TMP/out"
[[ ! -e "$SSH_MARKER" ]] || { echo 'FAIL: touched host before security gate' >&2; exit 1; }
if printf '%s\n' demo-site | GH_TEST_BRANCH=development PATH="$TMP/bin:$PATH" bash "$ROOT/scripts/setup.sh" --repo example/private-site --project demo-site --host admin@server --apply > "$TMP/out" 2>&1; then
    echo 'FAIL: accepted unsupported default branch' >&2; exit 1
fi
grep -q 'requires main' "$TMP/out"
[[ ! -e "$SSH_MARKER" ]] || exit 1
echo 'PASS: unprotected or unsupported branches cannot mutate host'
