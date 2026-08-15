#!/usr/bin/env bash
# notify.sh — Phase 2 stub (DESIGN.md §10). Will send a Slack DM at exactly
# three moments: Gate 1 reached, Gate 2 reached, item parked. Until then it
# just prints, so the pipeline can call it unconditionally.
#
#   notify.sh <run-id> gate1|gate2|parked <summary...>
set -euo pipefail
run=${1:?usage: notify.sh <run-id> gate1|gate2|parked <summary...>}
kind=${2:?usage: notify.sh <run-id> gate1|gate2|parked <summary...>}
shift 2
echo "[notify:$kind] $run — ${*:-'(no summary)'}"
