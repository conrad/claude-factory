# Plan — Show deployment outcome + recent-deployments sidebar on the deploy page

- **Run:** 2026-08-15-deploy-status-feedback
- **Revision:** 0
- **Based on:** investigation.md

---

## DECISION NEEDED (read first — Gate 1)

The spec is deliberately hedged ("If it's possible" / "If possible"). Four
genuine product/architecture forks below cannot be picked silently. Each lists
my **RECOMMENDED** option (the Steps/Tests below are written against these) and
the tradeoff of the alternative. Say "approve" to take all recommendations, or
name a fork to redirect.

The three deliverables are **separable** — you can approve a subset:
AC #1 (outcome, Steps 1–3 + 8–9), AC #2 (sidebar layout, Step 6), AC #3
(recent-deployments metadata, Steps 4–5 + 7 + 8–9). AC #2 and AC #3 are most
useful together; AC #1 stands alone.

### Fork A — How do we show deploy *outcome*? (AC #1; open questions #1, #2, #6)

`workflow_dispatch` returns 204 with no run ID (`trigger.go:42-50`). Outcome can
only be observed by listing the workflow's recent runs and heuristically taking
the most recent one for that app's repo, then reading its `status`/`conclusion`.

- **RECOMMENDED — A1: client-side poll of a new backend status endpoint.**
  After a successful dispatch, `deploy.js` polls `GET /api/deploy-status?app=X`
  (new), which calls a new `githubactions.ListWorkflowRuns` and returns the most
  recent `workflow_dispatch` run's `status`/`conclusion`. The toast/inline
  status advances triggered → in-progress → succeeded/failed. Mirrors the repo's
  existing submit→poll precedent (`get_eval_response.go` + `eval/client.go`).
  *Rationale:* delivers real observable outcome with an established local
  pattern and no new infrastructure.
  *Tradeoff:* the run match is a heuristic (most-recent by `created_at`), so two
  rapid re-deploys of the same app can show the wrong run's outcome (mitigated,
  not eliminated — see Risks). And per open question #2, the workflow YAML lives
  in each `Handshake-Learn-Apps/<app>` repo and is unreadable from here, so a
  green `conclusion` means "the GitHub Actions run succeeded," which we must
  label honestly rather than as "deployment verified."
- Alternative — A0: don't observe outcome; only reword the current toast to be
  honest ("Deploy started — check GitHub Actions for the result"). Near-zero
  cost, but does not satisfy AC #1's intent.

### Fork B — Where does "user who initiated" come from? (AC #3; open question #3)

GitHub records the App/bot as the run actor, so the human is **not** recoverable
from GitHub. The only source is the inbound `Hs-Current-User-Id` session header
(numeric ID only), which must be captured **at dispatch time** — it cannot be
reconstructed later.

- **RECOMMENDED — B1: capture the numeric `Hs-Current-User-Id` at dispatch and
  store it.** Sidebar shows `User <id>` (or "unknown" when blank, e.g. local
  dev). *Rationale:* simplest, accurate, no extra network dependency.
  *Tradeoff:* shows a numeric ID, not a name/email.
- Alternative — B2: additionally resolve the ID to name/email via a GraphQL
  `currentUserProfile` call at dispatch (pattern exists in
  `current_user_profile.go`). Friendlier, but adds a GraphQL round-trip on the
  deploy path and a dependency on the gql proxy from the deploy subdomain.
- Fallback — B3: omit the user entirely. Only if B1 is rejected.

### Fork C — Where does "recent deployments" data live? (AC #2/#3; open question #4)

There is no database; the only persistence primitive is the already-injected GCS
`*storage.Client`. In-memory is rejected outright (investigation: `-race`- and
replica-unsafe).

- **RECOMMENDED — C1: write one small JSON record to GCS at dispatch time**
  (app, environment, userId, triggeredAt) under a reserved `_deployments/`
  prefix; the sidebar reads the most recent N records via a new
  `GET /api/deployments`. *Rationale:* the only option that yields the real
  human user + timestamp + subdomain the spec asks for; uses the existing
  client; no shared in-process state (`-race`-safe). Recorded as ADR-001.
  *Tradeoff:* the sidebar shows *dispatch* records, not GitHub-verified outcome
  (outcome for the just-triggered deploy is covered live by Fork A). Requires
  excluding the reserved prefix from `ServeAppsList` (see Risks).
- Alternative — C2: query GitHub's runs-list live on each page load. Gives
  timestamp but only the **bot** actor (fails AC #3's "user"), and no clean
  subdomain list. Rejected as the primary source for AC #3.

---

## Approach

Three additive, independently-approvable pieces, all following existing repo
conventions (one `*Handler` with injectable func seams for GitHub/storage;
`RequireAuth(w, r, "deploy")` on every method; vanilla-JS `fetch`+`then` with
`showToast`; new outbound GitHub call in the `githubactions` package behind the
`githubAPIBase` test seam):

1. **Outcome (AC #1, Fork A1):** new `githubactions.ListWorkflowRuns`; new
   `GET /api/deploy-status?app=X` handler; `deploy.js` polls it after dispatch
   and advances an inline status line.
2. **Recent-deployments data (AC #3, Fork B1+C1):** `ServeDeployAPI` writes a
   GCS record at dispatch (best-effort, non-fatal), capturing app / environment
   / `Hs-Current-User-Id` / timestamp; new `GET /api/deployments` lists the most
   recent records; `ServeAppsList` learns to skip the reserved `_deployments/`
   prefix.
3. **Sidebar (AC #2):** restructure `.deploy-main` to add a right column and
   render the `/api/deployments` list into it.

No new mutable in-process shared state is introduced; all persistence is via GCS
network calls, so the `-race` CI run is unaffected.

## Steps

1. **Add `githubactions.ListWorkflowRuns`** — new file
   `internal/githubactions/runs.go`. `GET
   {githubAPIBase}/repos/{owner}/{repo}/actions/workflows/{workflowID}/runs?event=workflow_dispatch&branch=main&per_page={n}`,
   Bearer token, decode `{"workflow_runs":[...]}` into `[]WorkflowRun`. **Must
   use the package-level `githubAPIBase` var** (as `auth.go` does) so it is
   testable via an `httptest` server. (Note: existing `TriggerWorkflow`
   hardcodes `api.github.com`; leave it unchanged — only the new function needs
   the seam.)
2. **Add the status handler** — in `internal/api/handlers/deploy.go`, add
   `ServeDeployStatus(w, r)`: GET only; `RequireAuth(w, r, "deploy")`; read
   `app` from query; build `ownerRepo = "Handshake-Learn-Apps/" + app`; obtain an
   installation token (reuse the existing `InstallationTokenFunc` seam + config
   guard already in `ServeDeployAPI`); call the runs lister (behind a new
   `ListWorkflowRunsFunc` seam); return JSON for the most recent run. On empty
   list, return `{"status":"unknown"}`.
3. **Wire the outcome frontend** — in `web/static/js/deploy.js`, after a 2xx from
   `POST /deploy`, start polling `GET /api/deploy-status?app=<app>` (interval
   ~4s, capped ~2min) and update an inline status element until `status` is
   `completed` (then show `conclusion`) or the cap is hit. Keep `showToast` for
   the initial "Deploy started" and terminal success/failure.
4. **Write a deployment record at dispatch** — in `ServeDeployAPI` (deploy.go),
   after `trigger(...)` succeeds, build a `DeploymentRecord{App, Environment,
   UserID, TriggeredAt}` (UserID from `r.Header.Get("Hs-Current-User-Id")`) and
   persist it via a new `RecordDeploymentFunc` seam (default implementation in
   new file `internal/api/handlers/deploy_records.go` writes JSON to
   `_deployments/<RFC3339Nano>-<app>.json` in `LearnAppsBucket`). **Best-effort:**
   a write error is logged and ignored — it must not fail the deploy response.
5. **Add the deployments-list handler** — `ServeDeployments(w, r)` in deploy.go:
   GET only; `RequireAuth(w, r, "deploy")`; list objects under `_deployments/`
   via a new `ListDeploymentsFunc` seam (default impl in `deploy_records.go`),
   sort desc by `TriggeredAt`, cap at 20, return
   `{"deployments":[...]}`.
6. **Sidebar layout** — `web/template/deploy.html`: add a right-column container
   (e.g. `<aside id="recent-deploys" class="deploy-recent">`) inside/alongside
   `.deploy-main`. `web/static/css/deploy.css`: widen `body` `max-width` and give
   the sidebar a fixed/min column in the existing `.deploy-main` flex row;
   collapse below the existing `36rem` breakpoint. `deploy.js`: on load, `fetch
   /api/deployments` and render rows (app · date/time · `User <id>`), with
   loading/empty/error states like the app list.
7. **Exclude the reserved prefix from the app list** — in `ServeAppsList`, skip
   any prefix/name that is reserved (extract `isReservedAppName(name) bool`
   returning true for `_deployments` and any name starting with `_`), so the
   records directory never appears as a fake app.
8. **Router wiring** — `internal/api/router/router.go`: mount `Get
   "/api/deploy-status"` and `Get "/api/deployments"` on **both** `mainRouter`
   (path-based) and `deployRouter` (deploy subdomain), matching how `/api/apps`
   is mounted. Do **not** add them to `appsRouter` (sidebar is deploy-page only).
9. **Tests** — see Test strategy; add `runs_test.go`, extend `deploy_test.go`.

## Files to touch

- `internal/githubactions/runs.go` — **new.** `WorkflowRun` struct +
  `ListWorkflowRuns`, using `githubAPIBase`.
- `internal/githubactions/runs_test.go` — **new.** `httptest` + `githubAPIBase`
  override; asserts URL/query and JSON decode.
- `internal/api/handlers/deploy.go` — add `ListWorkflowRunsFunc`,
  `RecordDeploymentFunc`, `ListDeploymentsFunc` seams + `DeploymentRecord`
  struct; add `ServeDeployStatus`, `ServeDeployments`; record write in
  `ServeDeployAPI`; `isReservedAppName` + filter in `ServeAppsList`.
- `internal/api/handlers/deploy_records.go` — **new.** Default GCS
  read/write impls behind the record seams (keeps deploy.go lean).
- `internal/api/handlers/deploy_test.go` — extend: status endpoint, deployments
  endpoint, record capture from header, reserved-prefix filter.
- `internal/api/router/router.go` — mount the two new GET routes on mainRouter +
  deployRouter.
- `web/template/deploy.html` — sidebar container.
- `web/static/css/deploy.css` — widen body; sidebar column; responsive collapse.
- `web/static/js/deploy.js` — post-dispatch status polling; sidebar fetch/render.

## Interfaces

`internal/githubactions/runs.go`:

```go
type WorkflowRun struct {
    ID         int64     `json:"id"`
    Status     string    `json:"status"`      // queued | in_progress | completed
    Conclusion string    `json:"conclusion"`  // success | failure | cancelled | "" while running
    Event      string    `json:"event"`
    HTMLURL    string    `json:"html_url"`
    CreatedAt  time.Time `json:"created_at"`
}

// GET {githubAPIBase}/repos/{owner}/{repo}/actions/workflows/{workflowID}/runs
//   ?event=workflow_dispatch&branch=main&per_page={perPage}
func ListWorkflowRuns(ownerRepo, token, workflowID string, perPage int) ([]WorkflowRun, error)
```

`internal/api/handlers/deploy.go` (new seams + record type):

```go
type ListWorkflowRunsFunc func(ownerRepo, token, workflowID string, perPage int) ([]githubactions.WorkflowRun, error)
type RecordDeploymentFunc func(ctx context.Context, rec DeploymentRecord) error
type ListDeploymentsFunc  func(ctx context.Context, limit int) ([]DeploymentRecord, error)

type DeploymentRecord struct {
    App         string    `json:"app"`
    Environment string    `json:"environment"`
    UserID      string    `json:"userId"`       // numeric Hs-Current-User-Id; may be ""
    TriggeredAt time.Time `json:"triggeredAt"`
}
```

New endpoints (both auth-gated with `RequireAuth(w, r, "deploy")`):

```
GET /api/deploy-status?app=<app>
  200 {"app":"x","status":"completed","conclusion":"success","runId":123,
       "htmlUrl":"https://github.com/...","createdAt":"2026-08-15T..Z"}
  200 {"status":"unknown"}   // no runs found yet
  400 missing app · 405 non-GET · 500 token/github error

GET /api/deployments
  200 {"deployments":[{"app":"x","environment":"staging","userId":"123",
        "triggeredAt":"2026-08-15T..Z"}, ...]}   // desc by triggeredAt, max 20
  405 non-GET
```

GCS record object: `_deployments/<RFC3339Nano>-<app>.json` in `LearnAppsBucket`,
body = JSON of `DeploymentRecord`.

## Test strategy

Each test fails before the change, passes after.

- **AC #1 (outcome), `internal/githubactions/runs_test.go`:** override
  `githubAPIBase` with an `httptest.Server` that asserts the request path and
  query (`event=workflow_dispatch`, `branch=main`, `per_page`) and returns a
  canned `{"workflow_runs":[...]}`; assert `ListWorkflowRuns` parses `status`,
  `conclusion`, `created_at`, `html_url`. Add a non-2xx case → error. *(Fails
  before: function does not exist.)*
- **AC #1 (outcome), `deploy_test.go` → `ServeDeployStatus`:** inject
  `ListWorkflowRunsFunc`; (a) run with `status:"completed", conclusion:"success"`
  → JSON reports success; (b) `status:"in_progress", conclusion:""` → reports
  in-progress; (c) empty slice → `{"status":"unknown"}`; (d) missing `app` → 400;
  (e) non-GET → 405. Token acquisition uses the existing `InstallationTokenFunc`
  seam (as in the current API tests).
- **AC #2 (sidebar), `deploy_test.go` → `ServeDeployPage`:** extend the existing
  200/HTML test to assert the body contains the sidebar container id
  (`recent-deploys`). *(Fails before: id absent.)* JS rendering itself has no Go
  harness in this repo (vanilla JS, no test runner) — its data contract is
  covered by the `/api/deployments` handler test; note manual verification of
  the rendered sidebar.
- **AC #3 (metadata), `deploy_test.go` → `ServeDeployAPI`:** set request header
  `Hs-Current-User-Id: 123`; inject `RecordDeploymentFunc` capturing the record;
  assert `App`, `Environment` (staging in dev), and `UserID=="123"`; assert a
  record-write *error* is swallowed (response still 200 `{"status":"ok"}`).
- **AC #3 (metadata), `deploy_test.go` → `ServeDeployments`:** inject
  `ListDeploymentsFunc` returning three unordered records; assert the response is
  JSON sorted desc by `triggeredAt` and shape-correct.
- **AC #3 (metadata), `deploy_test.go` → `isReservedAppName`:** table test:
  `_deployments`→true, `_x`→true, `myapp`→false, `example`→false. Guards the
  fake-app regression.

## Risks & rollback

- **Heuristic run match (Fork A / OQ #1)** → the status endpoint takes the most
  recent `workflow_dispatch` run; two rapid re-deploys of the same app can
  surface the wrong run. *Mitigation:* query `event=workflow_dispatch&branch=main`
  and (optionally) have the frontend pass its dispatch timestamp so the backend
  ignores runs created before it; document the limitation in the handler doc
  comment. Acceptable for a status hint; not a correctness guarantee.
- **`conclusion` semantics unverifiable (OQ #2)** → the workflow YAML lives in
  the per-app repo. *Mitigation:* label the UI "workflow succeeded/failed"
  (linking to the run's `html_url`), never "deployment verified"; note the
  assumption in the ADR.
- **Reserved prefix leaking into the app list** → `ServeAppsList` lists top-level
  prefixes with delimiter `/`, so `_deployments/` would otherwise appear as an
  app. *Mitigation:* Step 7 filter + `isReservedAppName` test.
- **GCS write latency/failure at dispatch** → *Mitigation:* record write is
  best-effort and non-fatal; deploy response is unchanged on write error.
- **`-race` / replicas** → no new in-process shared mutable state; all state is
  GCS objects. Called out per repo conventions.
- **Auth** → both new endpoints call `RequireAuth(w, r, "deploy")` exactly like
  the sibling handlers.
- **Rollback:** revert the commit — all changes are additive (new files, new
  routes, additive template/CSS/JS). Any `_deployments/` objects already written
  are inert (ignored by the app list once the filter ships; harmless if the
  filter is also reverted, as they simply reappear as a single `_deployments`
  "app" — delete the prefix if that occurs).

## Out of scope

- Persisting/patching GitHub-verified outcome into sidebar rows (sidebar shows
  dispatch app/time/user; live outcome is only for the just-triggered deploy via
  AC #1). *Future.*
- Resolving numeric user ID → name/email via GraphQL (Fork B2). *Future.*
- Real-time cross-replica push (websockets/SSE).
- Garbage-collecting / paginating old `_deployments/` records beyond the recent
  20 returned. *Future.*
- Refactoring `TriggerWorkflow` to use `githubAPIBase`, or touching the unused
  `internal/gcsdeploy` dead code.
- Any change to the per-app `publish-to-gcs.yml` workflow.

## ADR

Draft ADR-001 below (finalized by the documenter):

---

### ADR-001: Persist deploy metadata to GCS records rather than live GitHub or in-memory

- **Date:** 2026-08-15
- **Status:** accepted
- **Run:** 2026-08-15-deploy-status-feedback

**Context.** The deploy page must show recent deployments with the human user,
timestamp, and subdomain (AC #3). learn-apps has no database; the only
persistence primitive is the injected GCS `*storage.Client`. GitHub cannot supply
the human user (the App/bot is the run actor) and only exposes it at dispatch
time via the `Hs-Current-User-Id` header. In-memory storage is `-race`- and
replica-unsafe.

**Decision.** At dispatch, `ServeDeployAPI` writes a small JSON record
(app, environment, userId, triggeredAt) to `_deployments/<ts>-<app>.json` in the
existing GCS bucket; the sidebar reads recent records via `GET /api/deployments`.
Live GitHub is used only for the separate real-time *outcome* of the
just-triggered deploy (AC #1), never as the source of the recent-deployments
list.

**Alternatives considered.**
- Live GitHub runs-list as the sidebar source — rejected: yields the bot actor,
  not the human, and no clean subdomain list.
- In-memory ring buffer — rejected: `-race`- and replica-unsafe.

**Consequences.** Accurate human user + timestamp + subdomain with no new
infrastructure and no new shared in-process state. Introduces a reserved
`_deployments/` prefix that `ServeAppsList` must exclude. Records accumulate
unbounded until a future GC step; the list endpoint caps reads at the most recent
20.
