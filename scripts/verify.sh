#!/usr/bin/env bash
# verify.sh — quality layer 1 (DESIGN.md §3.7, §5): run a repo's verification
# steps; on the first failure, write a structured failure report into the run
# and exit 1. Deterministic — no model calls.
#
#   verify.sh <repo-name> <run-id>
#
# Steps come from repos/<name>.yaml under `verify:` (order preserved).
set -euo pipefail

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "verify.sh: $*" >&2; exit 2; }

repo=${1:?usage: verify.sh <repo-name> <run-id>}
run=${2:?usage: verify.sh <repo-name> <run-id>}
cfg="$FACTORY_DIR/repos/$repo.yaml"
run_dir="$FACTORY_DIR/runs/$run"
[[ -f "$cfg" ]] || die "no repo config: repos/$repo.yaml"
[[ -d "$run_dir" ]] || die "no such run: $run"

repo_path=$(sed -n 's/^path: *//p' "$cfg" | head -1)
[[ -d "$repo_path" ]] || die "repo path does not exist: $repo_path"

# Extract `  key: command` lines from the verify: block (stop at next
# top-level key). Strip optional surrounding quotes from commands.
steps=$(awk '
  /^verify:/ { inblock=1; next }
  inblock && /^[^ ]/ { inblock=0 }
  inblock && /^  [A-Za-z0-9_-]+: / { print }
' "$cfg")
[[ -n "$steps" ]] || die "no verify: steps in repos/$repo.yaml"

mkdir -p "$run_dir/attempts"
attempt=$(sed -n 's/^attempts_build: *//p' "$run_dir/item.yaml" | head -1)
attempt=${attempt:-0}
log="$run_dir/attempts/verify-output-$attempt.log"
: > "$log"

while IFS= read -r line; do
  name=$(echo "$line" | sed 's/^  \([A-Za-z0-9_-]*\):.*/\1/')
  cmd=$(echo "$line" | sed 's/^  [A-Za-z0-9_-]*: *//; s/^"\(.*\)"$/\1/')
  echo "==> $name: $cmd" | tee -a "$log"
  rc=0
  (cd "$repo_path" && bash -c "$cmd") >> "$log" 2>&1 || rc=$?
  if [[ $rc -ne 0 ]]; then
    report="$run_dir/attempts/failure-report-$attempt.md"
    {
      echo "# Failure report — attempt $attempt"
      echo
      echo "- **When:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "- **Failed step:** \`$name\` (\`$cmd\`, exit $rc)"
      echo "- **Repo:** $repo ($repo_path)"
      echo
      echo "## Output (last 80 lines)"
      echo
      echo '```'
      tail -80 "$log"
      echo '```'
      echo
      echo "## Suspected cause"
      echo
      echo "_(filled in by the orchestrator or reviewer before the builder retries)_"
    } > "$report"
    echo "FAIL: $name — report written to runs/$run/attempts/failure-report-$attempt.md" >&2
    exit 1
  fi
done <<< "$steps"

echo "PASS: all verify steps green (log: runs/$run/attempts/verify-output-$attempt.log)"
