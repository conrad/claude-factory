# My Factory

A software factory: work items (a prompt or a Linear ticket) flow through a
graph of agents and deterministic scripts — investigate → plan → **your
approval** → build → verify → review → **your approval** → merged PR — with
bounded retries, structured failure reports, and a full audit trail per run.

Architecture and rationale: **[DESIGN.md](DESIGN.md)**. Current status: Phase 1
(walking skeleton) built; quality organs (test-writer, adversarial review
panel, security, conformance) arrive in Phase 2.

## Get started (5 minutes)

Open Claude Code in this directory, then:

**1. Register your first target repo:**

```
/factory add-repo myrepo /absolute/path/to/repo
```

This detects the repo's lint/typecheck/test commands and writes
`repos/myrepo.yaml`. Review it — especially the `verify:` steps (they are
quality gate #1) and `conventions:`.

**2. Send a small task through:**

```
/factory new myrepo Fix the <something small you know is broken>
```

The factory investigates, plans, and stops. You'll get the plan with approach,
steps, test strategy, and out-of-scope list.

**3. Decide at Gate 1:**

```
/factory approve <run-id>
/factory revise <run-id> use the existing retry helper instead
/factory reject <run-id> not worth doing
```

On approve, the factory writes tests (red first), builds until they pass, runs
the repo's full verify suite (bounded to 3 attempts, then it parks and tells
you why), opens a PR, and stops again.

**4. Decide at Gate 2:** same verbs. `approve` merges the PR and closes out;
`revise <comments>` sends your review feedback back to the builder.

**Anytime:** `/factory status` · `/factory resume <run-id>` (continues parked
or interrupted runs — all state is on disk, any session can pick up any run).
**Linear intake:** `/factory pull HAI-123`.

## Layout

| Path | What |
|---|---|
| `DESIGN.md` | The architecture — read this first |
| `.claude/skills/factory/` | The orchestrator (`/factory` command) |
| `agents/` | Agent role contracts (investigator, planner, builder, integrator; more in Phase 2) |
| `repos/` | One YAML per target repo (`_example.yaml` is the template) |
| `scripts/state.sh` | The state machine — sole writer of run state |
| `scripts/verify.sh` | Runs a repo's verify steps; writes failure reports |
| `scripts/smoke-test.sh` | Acceptance test — run after changing any script |
| `templates/` | Skeletons for spec, plan, failure report, run report, ADR |
| `runs/` | One directory per work item: state, artifacts, audit trail |

## Rules of the road

- Only `scripts/state.sh` mutates run state. Agents and humans write
  documents; the state machine validates every transition.
- The factory never merges without an explicit `gate merge approve` recorded
  in the run's `item.yaml`.
- After editing any script: `scripts/smoke-test.sh` must pass.
