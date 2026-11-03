#!/usr/bin/env bash
# Guided multi-project bootstrap. Each entry remains an independent guarded setup.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE='' MODE='plan'
while (( $# )); do
  case "$1" in
    --file) FILE="${2:?missing file}"; shift 2;;
    --plan) MODE=plan; shift;;
    --apply) MODE=apply; shift;;
    *) echo 'Usage: bash scripts/setup-fleet.sh --file fleet.tsv [--plan|--apply]' >&2; exit 2;;
  esac
done
[[ -r "$FILE" ]] || { echo 'Readable fleet TSV required' >&2; exit 2; }
if [[ "$MODE" == apply ]]; then
  printf 'Type APPLY-FLEET to confirm initiating real configuration: '
  read -r ANSWER
  [[ "$ANSWER" == APPLY-FLEET ]] || exit 1
fi
COUNT=0
while IFS=$'\t' read -r PROJECT REPO HOST ASSET EXTRA; do
  [[ -z "$PROJECT" || "$PROJECT" == \#* ]] && continue
  [[ -z "$EXTRA" ]] || { echo 'Unexpected extra TSV column' >&2; exit 2; }
  [[ -n "$REPO" && -n "$HOST" ]] || { echo 'Incomplete TSV entry' >&2; exit 2; }
  (( COUNT+=1 ))
  args=(--project "$PROJECT" --repo "$REPO" --host "$HOST")
  if [[ -n "$ASSET" ]]; then args+=(--asset-dir "$ASSET"); fi
  bash "$ROOT/scripts/setup.sh" "${args[@]}" "--$MODE"
done < "$FILE"
(( COUNT > 0 )) || { echo 'Empty fleet configuration' >&2; exit 2; }
echo "Processed entries: $COUNT"
