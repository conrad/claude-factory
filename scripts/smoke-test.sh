#!/usr/bin/env bash
# smoke-test.sh — Phase 0 acceptance test. Walks a throwaway run through the
# full lifecycle: gates (incl. a revise), a verify failure + failure report,
# the retry loop, park/resume, invalid-transition rejection, and terminal
# freezing. Cleans up after itself. Exit 0 = state machine healthy.
set -euo pipefail

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$FACTORY_DIR"
FAKE_REPO=$(mktemp -d)
trap 'rm -rf "$FAKE_REPO" repos/_smoke.yaml runs/"${RUN:-nonexistent}"' EXIT

fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }
expect_fail() { "$@" >/dev/null 2>&1 && fail "expected rejection: $*" || true; }

touch "$FAKE_REPO/FAIL"
cat > repos/_smoke.yaml <<EOF
name: _smoke
path: $FAKE_REPO
default_branch: main
verify:
  lint: echo linting ok
  test: test ! -f FAIL || (echo 'simulated test failure' && exit 1)
EOF

RUN=$(scripts/state.sh new "smoke-$$" _smoke prompt Smoke test)

expect_fail scripts/state.sh set "$RUN" BUILDING            # invalid transition

for s in TRIAGED INVESTIGATING PLANNING AWAITING_PLAN_APPROVAL; do
  scripts/state.sh set "$RUN" "$s" >/dev/null
done
scripts/state.sh gate "$RUN" plan revise tighten tests >/dev/null
scripts/state.sh set "$RUN" AWAITING_PLAN_APPROVAL >/dev/null
scripts/state.sh gate "$RUN" plan approve >/dev/null
[[ $(scripts/state.sh field "$RUN" attempts_plan_revisions) == 1 ]] || fail "plan revision not counted"

scripts/state.sh set "$RUN" BUILDING >/dev/null
scripts/state.sh set "$RUN" VERIFYING >/dev/null
expect_fail scripts/verify.sh _smoke "$RUN"                 # red verify
[[ -f "runs/$RUN/attempts/failure-report-0.md" ]] || fail "no failure report"

scripts/state.sh bump "$RUN" build >/dev/null
scripts/state.sh set "$RUN" BUILDING retry >/dev/null
scripts/state.sh set "$RUN" VERIFYING >/dev/null
rm "$FAKE_REPO/FAIL"
scripts/verify.sh _smoke "$RUN" >/dev/null                  # green verify

scripts/state.sh park "$RUN" test >/dev/null
expect_fail scripts/state.sh set "$RUN" REVIEWING           # parked refuses set
scripts/state.sh resume "$RUN" >/dev/null

for s in REVIEWING DOCUMENTING INTEGRATING AWAITING_MERGE_APPROVAL; do
  scripts/state.sh set "$RUN" "$s" >/dev/null
done
scripts/state.sh gate "$RUN" merge approve >/dev/null
scripts/state.sh set "$RUN" DONE >/dev/null
expect_fail scripts/state.sh set "$RUN" BUILDING            # terminal frozen

echo "SMOKE PASS: full lifecycle, failure loop, park/resume, gate counting, terminal freeze"
