#!/usr/bin/env bash
# state.sh — the only writer of run state (DESIGN.md §7).
#
#   state.sh new <slug> <repo> <source> [title...]   create a run, state=INTAKE
#   state.sh get <run-id>                            print current state
#   state.sh set <run-id> <STATE> [note...]          validated transition
#   state.sh gate <run-id> plan|merge approve|revise|reject [comments...]
#   state.sh bump <run-id> build|plan_revisions      increment a counter
#   state.sh park <run-id> [note...]                 park from any active state
#   state.sh resume <run-id> [note...]               resume to parked_from state
#   state.sh field <run-id> <key> [value]            get/set a scalar field
#   state.sh list                                    table of all runs
set -euo pipefail

FACTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS_DIR="$FACTORY_DIR/runs"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

die() { echo "state.sh: $*" >&2; exit 1; }

# Allowed transitions (DESIGN.md §7). "FROM:TO1,TO2" — PARKED handled separately.
TRANSITIONS='
INTAKE:TRIAGED,CLOSED
TRIAGED:INVESTIGATING,BUILDING,CLOSED
INVESTIGATING:PLANNING
PLANNING:AWAITING_PLAN_APPROVAL
AWAITING_PLAN_APPROVAL:WRITING_TESTS,PLANNING,CLOSED
WRITING_TESTS:BUILDING
BUILDING:VERIFYING
VERIFYING:REVIEWING,BUILDING
REVIEWING:DOCUMENTING,BUILDING
DOCUMENTING:INTEGRATING
INTEGRATING:AWAITING_MERGE_APPROVAL
AWAITING_MERGE_APPROVAL:MERGING,BUILDING,CLOSED
MERGING:DONE
'
TERMINAL="DONE CLOSED"

item_file() {
  local f="$RUNS_DIR/$1/item.yaml"
  [[ -f "$f" ]] || die "no such run: $1"
  echo "$f"
}

get_field() { # <file> <key>
  sed -n "s/^$2: *//p" "$1" | head -1
}

set_field() { # <file> <key> <value>  (value must not contain | or newlines)
  local esc=${3//|/-}
  sed -i.bak "s|^$2: .*|$2: $esc|" "$1" && rm -f "$1.bak"   # -i.bak works on BSD and GNU sed
}

log_json() { # <run> <from> <to> [note] — telemetry seam (future Datadog ship)
  local note=${4:-}; note=${note//\"/\'}
  printf '{"ts":"%s","run":"%s","from":"%s","to":"%s","note":"%s"}\n' \
    "$(now)" "$1" "$2" "$3" "$note" >> "$RUNS_DIR/factory.log.jsonl"
}

log_history() { # <text> <file>
  printf '  - %s %s\n' "$(now)" "$1" >> "$2"
}

valid_transition() { # <from> <to>
  local allowed
  allowed=$(echo "$TRANSITIONS" | sed -n "s/^$1://p")
  [[ ",$allowed," == *",$2,"* ]]
}

do_set() { # <run-id> <new-state> <note>
  local run=$1 to=$2 note=${3:-}
  local f from
  f=$(item_file "$run")
  from=$(get_field "$f" state)
  [[ " $TERMINAL " == *" $from "* ]] && die "$run is $from (terminal); cannot transition"
  if [[ "$from" == "PARKED" ]]; then
    die "$run is PARKED; use 'state.sh resume $run'"
  fi
  valid_transition "$from" "$to" || die "invalid transition for $run: $from -> $to"
  set_field "$f" state "$to"
  set_field "$f" updated "$(now)"
  log_history "$from -> $to${note:+ ($note)}" "$f"
  log_json "$run" "$from" "$to" "$note"
  echo "$run: $from -> $to"
}

cmd=${1:-help}
case "$cmd" in
  new)
    [[ $# -ge 4 ]] || die "usage: state.sh new <slug> <repo> <source> [title...]"
    slug=$2 repo=$3 source=$4; shift 4; title=${*:-$slug}
    [[ "$source" == prompt || "$source" == linear:* ]] || die "source must be 'prompt' or 'linear:<ID>'"
    repo_cfg="$FACTORY_DIR/repos/$repo.yaml"
    [[ -f "$repo_cfg" ]] || die "no repo config: repos/$repo.yaml"
    id="$(date +%Y-%m-%d)-$slug"
    dir="$RUNS_DIR/$id"
    [[ -e "$dir" ]] && die "run already exists: $id"
    mkdir -p "$dir/attempts" "$dir/review"
    cp "$FACTORY_DIR/templates/item.yaml" "$dir/item.yaml"
    set_field "$dir/item.yaml" id "$id"
    set_field "$dir/item.yaml" repo "$repo"
    set_field "$dir/item.yaml" source "$source"
    set_field "$dir/item.yaml" title "$title"
    set_field "$dir/item.yaml" created "$(now)"
    set_field "$dir/item.yaml" updated "$(now)"
    log_history "created (source=$source)" "$dir/item.yaml"
    echo "$id"
    ;;
  get)
    f=$(item_file "${2:?usage: state.sh get <run-id>}")
    get_field "$f" state
    ;;
  set)
    [[ $# -ge 3 ]] || die "usage: state.sh set <run-id> <STATE> [note...]"
    run=$2 to=$3; shift 3
    do_set "$run" "$to" "${*:-}"
    ;;
  gate)
    [[ $# -ge 4 ]] || die "usage: state.sh gate <run-id> plan|merge approve|revise|reject [comments...]"
    run=$2 gate=$3 decision=$4; shift 4; comments=${*:-}
    f=$(item_file "$run")
    from=$(get_field "$f" state)
    case "$gate:$decision" in
      plan:approve)  [[ "$from" == AWAITING_PLAN_APPROVAL ]] || die "$run is $from, not AWAITING_PLAN_APPROVAL"; to=WRITING_TESTS ;;
      plan:revise)   [[ "$from" == AWAITING_PLAN_APPROVAL ]] || die "$run is $from, not AWAITING_PLAN_APPROVAL"; to=PLANNING ;;
      plan:reject)   [[ "$from" == AWAITING_PLAN_APPROVAL ]] || die "$run is $from, not AWAITING_PLAN_APPROVAL"; to=CLOSED ;;
      merge:approve) [[ "$from" == AWAITING_MERGE_APPROVAL ]] || die "$run is $from, not AWAITING_MERGE_APPROVAL"; to=MERGING ;;
      merge:revise)  [[ "$from" == AWAITING_MERGE_APPROVAL ]] || die "$run is $from, not AWAITING_MERGE_APPROVAL"; to=BUILDING ;;
      merge:reject)  [[ "$from" == AWAITING_MERGE_APPROVAL ]] || die "$run is $from, not AWAITING_MERGE_APPROVAL"; to=CLOSED ;;
      *) die "gate must be plan|merge, decision must be approve|revise|reject" ;;
    esac
    set_field "$f" "gate_$gate" "$decision $(now)${comments:+ $comments}"
    if [[ "$gate:$decision" == plan:revise ]]; then
      n=$(get_field "$f" attempts_plan_revisions); set_field "$f" attempts_plan_revisions $((n + 1))
    fi
    do_set "$run" "$to" "gate:$gate $decision${comments:+: $comments}"
    ;;
  bump)
    [[ $# -eq 3 ]] || die "usage: state.sh bump <run-id> build|plan_revisions"
    f=$(item_file "$2")
    key="attempts_$3"
    n=$(get_field "$f" "$key"); [[ -n "$n" ]] || die "unknown counter: $3"
    set_field "$f" "$key" $((n + 1))
    log_history "bump $key -> $((n + 1))" "$f"
    echo $((n + 1))
    ;;
  park)
    run=${2:?usage: state.sh park <run-id> [note...]}; shift 2
    f=$(item_file "$run")
    from=$(get_field "$f" state)
    [[ " $TERMINAL PARKED " == *" $from "* ]] && die "$run is $from; cannot park"
    set_field "$f" parked_from "$from"
    set_field "$f" state PARKED
    set_field "$f" updated "$(now)"
    log_history "$from -> PARKED${*:+ ($*)}" "$f"
    log_json "$run" "$from" PARKED "${*:-}"
    echo "$run: $from -> PARKED"
    ;;
  resume)
    run=${2:?usage: state.sh resume <run-id> [note...]}; shift 2
    f=$(item_file "$run")
    [[ "$(get_field "$f" state)" == PARKED ]] || die "$run is not PARKED"
    to=$(get_field "$f" parked_from)
    [[ -n "$to" ]] || die "$run has no parked_from state"
    set_field "$f" state "$to"
    set_field "$f" parked_from ""
    set_field "$f" updated "$(now)"
    log_history "PARKED -> $to (resume${*:+: $*})" "$f"
    log_json "$run" PARKED "$to" "resume${*:+: $*}"
    echo "$run: PARKED -> $to"
    ;;
  field)
    [[ $# -ge 3 ]] || die "usage: state.sh field <run-id> <key> [value]"
    f=$(item_file "$2")
    if [[ $# -eq 3 ]]; then
      get_field "$f" "$3"
    else
      [[ "$3" == state || "$3" == parked_from ]] && die "use set/park/resume for state fields"
      grep -q "^$3: " "$f" || die "unknown field: $3"
      set_field "$f" "$3" "${*:4}"
      set_field "$f" updated "$(now)"
    fi
    ;;
  list)
    printf '%-40s %-24s %-12s %s\n' RUN STATE REPO UPDATED
    for f in "$RUNS_DIR"/*/item.yaml; do
      [[ -f "$f" ]] || continue
      printf '%-40s %-24s %-12s %s\n' \
        "$(get_field "$f" id)" "$(get_field "$f" state)" \
        "$(get_field "$f" repo)" "$(get_field "$f" updated)"
    done
    ;;
  *)
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
esac
