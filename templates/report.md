# Run report — {{title}}

- **Run:** {{run-id}} · **Repo:** {{repo}} · **Source:** {{source}}
- **Outcome:** {{merged | closed | parked}}
- **PR:** {{url}}
- **Attempts:** build {{n}}/{{budget}}, plan revisions {{n}}
- **Tokens:** {{total}} · **Wall time:** {{hours}}

## What was asked

{{Two sentences max, from spec.md.}}

## What was found

{{Investigation highlights that shaped the plan.}}

## What was planned

{{The approach, and anything you changed at Gate 1.}}

## What changed

{{Files + one line each. Deviations from plan, with justification.}}

## Quality gates

| Layer | Result | Notes |
|---|---|---|
| verify (lint/type/test) | {{pass after N attempts}} | |
| new tests | {{n written, red-first confirmed}} | |
| reviewer panel | {{survived / refuted xN}} | |
| security | {{clean / findings}} | |
| conformance | {{conforms / drift}} | |

## Learnings

{{What goes into CLAUDE.md deltas, and anything metrics-worthy. This section
feeds runs/metrics.jsonl (Phase 3).}}
