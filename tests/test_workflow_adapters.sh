#!/usr/bin/env bash
# Test workflow generation for each CI/CD adapter type.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Helper: render workflow with given artifact type
render_workflow() {
  local artifact_type="$1"
  local archive_name="$2"
  export PD_REPO=example/private-app
  export PD_PROJECT=demo-site
  export PD_LABEL=pd-demo-site
  export PD_ASSET_DIR=dist
  export PD_ARTIFACT_TYPE="$artifact_type"
  export PD_ARTIFACT_ARCHIVE="$archive_name"
  export PD_APP_DIR=dist
  export PD_BUILD_DIR=dist
  export PD_COMPOSE_DIR=dist
  export PD_SOURCE="$ROOT/templates/portico-deploy.yml"
  export PD_DEST="$(mktemp)"
  PD_SOURCE="$ROOT/templates/portico-deploy.yml" PD_DEST="$(mktemp)" python3 - <<'PY'
import os
from pathlib import Path
p=Path(os.environ["PD_SOURCE"]).read_text()
for a,b in {
    "@@REPO@@":os.environ["PD_REPO"],
    "@@PROJECT@@":os.environ["PD_PROJECT"],
    "@@RUNNER_LABEL@@":os.environ["PD_LABEL"],
    "@@ASSET_DIR@@":os.environ["PD_ASSET_DIR"],
    "@@ARTIFACT_TYPE@@":os.environ["PD_ARTIFACT_TYPE"],
    "@@ARTIFACT_ARCHIVE@@":os.environ["PD_ARTIFACT_ARCHIVE"],
    "@@APP_DIR@@":os.environ["PD_APP_DIR"],
    "@@BUILD_DIR@@":os.environ["PD_BUILD_DIR"],
    "@@COMPOSE_DIR@@":os.environ["PD_COMPOSE_DIR"],
}.items(): p=p.replace(a,b)
Path(os.environ["PD_DEST"]).write_text(p)
PY
}

# Test static adapter
echo "=== Testing static adapter ==="
render_workflow static artifact.tgz
if grep -q "static)" /tmp/rendered-workflow.yml; then
  echo "PASS: static adapter workflow contains static case"
else
  echo "FAIL: static adapter workflow missing static case" >&2
  exit 1
fi
if grep -q "tar -czf.*artifact.tgz" /tmp/rendered-workflow.yml; then
  echo "PASS: static adapter uses artifact.tgz"
else
  echo "FAIL: static adapter should use artifact.tgz" >&2
  exit 1
fi

# Test python adapter
echo "=== Testing python adapter ==="
render_workflow python artifact.tgz
if grep -q "pip install -r requirements.txt" /tmp/rendered-workflow.yml; then
  echo "PASS: python adapter includes pip install"
else
  echo "FAIL: python adapter missing pip install" >&2
  exit 1
fi

# Test nodejs adapter
echo "=== Testing nodejs adapter ==="
render_workflow nodejs artifact.tgz
if grep -q "npm ci" /tmp/rendered-workflow.yml; then
  echo "PASS: nodejs adapter includes npm ci"
else
  echo "FAIL: nodejs adapter missing npm ci" >&2
  exit 1
fi

# Test docker-compose adapter
echo "=== Testing docker-compose adapter ==="
render_workflow docker-compose artifact.tgz
if grep -q "docker-compose)" /tmp/rendered-workflow.yml; then
  echo "PASS: docker-compose adapter includes docker-compose case"
else
  echo "FAIL: docker-compose adapter missing docker-compose case" >&2
  exit 1
fi

echo "=== All adapter workflow generation tests complete ==="