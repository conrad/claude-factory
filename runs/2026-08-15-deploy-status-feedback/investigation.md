# Investigation — Show deployment outcome + recent-deployments sidebar on the deploy page

## Reproduction

Not a bug; confirming the spec's behavioral claim instead.

Confirmed by reading the full request/response path (no live run needed — the
code has no code path that could do otherwise):

- `POST /deploy` (`internal/api/handlers/deploy.go:149-200`, `ServeDeployAPI`)
  gets a GitHub App installation token, calls
  `githubactions.TriggerWorkflow` (a `workflow_dispatch` API call), and on
  success immediately writes `{"status":"ok"}` and returns — before the
  triggered workflow has done anything.
- The frontend (`web/static/js/deploy.js:302-330`) treats any 2xx response as
  final: it shows the toast **"Deploy triggered successfully."** and clears
  loading state. There is no follow-up poll, no run ID stored, nothing that
  ever asks "did the workflow finish, and how."
- GitHub's `workflow_dispatch` endpoint itself returns `204 No Content` with
  no run ID (`internal/githubactions/trigger.go:42-50` discards the response
  body entirely) — so even if the frontend wanted to check later, the backend
  today has nothing to check *with*.

Spec's claim is accurate: the user learns the *start request* was accepted,
never the deploy *outcome*.

## Where it lives

- Page template: `web/template/deploy.html` — plain server-rendered HTML, no
  JS framework, no htmx. Body is `max-width: 50rem` centered
  (`web/static/css/deploy.css:4-13`); `.deploy-main` is a flexbox row holding
  `.deploy-apps` (flex:1) and `.actions` (fixed min-width) — the layout has no
  existing sidebar region; adding a right sidebar means widening or
  restructuring this container, not just adding a `<div>`.
- Page serve: `DeployHandler.ServeDeployPage`
  (`internal/api/handlers/deploy.go:44-66`) — `html/template.ParseFS` +
  `Execute` with a `map[string]string{"RegisterAppsURL": ...}`. Any sidebar
  data (recent deployments) would need to be fetched here and added to that
  template data map (currently untyped `map[string]string`; a list of structs
  would need a real struct type).
- Deploy trigger: `DeployHandler.ServeDeployAPI`
  (`internal/api/handlers/deploy.go:149-200`) → `githubactions.TriggerWorkflow`
  (`internal/githubactions/trigger.go:17-51`), a `POST
  /repos/{owner}/{repo}/actions/workflows/publish-to-gcs.yml/dispatches`
  against `Handshake-Learn-Apps/<app>` (a **separate repo per app**, not this
  one), authenticated via a GitHub App installation token
  (`internal/githubactions/auth.go`, `InstallationAccessToken`).
- Frontend deploy click → confirm modal → fetch: `web/static/js/deploy.js:302-330`.

## Patterns to follow

- Handler pattern: one `*Handler` struct per feature, constructed once in
  `internal/api/router/router.go`, methods take `(w, r)`; auth is
  `h.auth.RequireAuth(w, r, "deploy")` gating every method
  (`internal/api/handlers/deploy.go:45-52`, `78-80`, `154-156`). Any new
  sidebar-data endpoint or extra template field follows this shape.
- Frontend pattern: vanilla JS IIFE per page (`deploy.js`), `fetch` +
  `.then/.catch`, `showToast` for user feedback, `setLoading` toggles a
  `body.loading` class (`web/static/js/deploy.js:222-224`). A polling-for-status
  addition would fit this same fetch/then style — no existing polling helper
  to reuse, though `internal/api/handlers/get_eval_response.go` +
  `eval/client.go` show this repo's *other* async-polling pattern
  (submit → return an ID → client polls a `/getEvalResponse/{id}`-style
  endpoint) if the planner wants a precedent for a similar client-poll loop
  here.
- Tests: `internal/api/handlers/deploy_test.go` uses
  `httptest.NewRecorder`/`NewRequest`, and injects `TriggerWorkflowFunc` /
  `InstallationTokenFunc` on the handler struct to fake GitHub calls
  (`deploy_test.go:157-224`) — the established seam for testing anything that
  calls out to GitHub. `internal/githubactions/auth_test.go` overrides the
  package-level `githubAPIBase` var to point at an `httptest.Server` — the
  seam for testing new githubactions API calls (e.g. listing workflow runs).

## Blast radius

- `DeployHandler` is constructed once in
  `internal/api/router/router.go` (`deploy := handlers.NewDeployHandler(...)`)
  and its methods are mounted on three routers: path-based (`/deploy`,
  `/api/apps`), the `deploy.<host>` subdomain router, and reused for
  `/api/apps` on the `apps.<host>` subdomain router. Changing
  `ServeDeployPage`'s template data or adding a new handler method touches all
  three mount points implicitly (same handler instance) but only the
  deploy-page routes render the sidebar.
- `githubactions.TriggerWorkflow` / `InstallationAccessToken` have no other
  callers in the repo (`grep` confirms only `deploy.go` uses them) — low risk
  of breaking something else, but also no existing "list runs" or "get run"
  function to build on; a new function would be net-new in this package.
- Current test coverage: `deploy_test.go` (page/list/API happy+error paths,
  auth redirects) and `router_test.go` (host routing). No test exercises
  outcome-polling or a sidebar today, since neither exists.
- `internal/gcsdeploy/deploy.go` (`PromoteDraftToCurrent`, `RollbackPreviousToCurrent`,
  `UnpublishCurrent`, `RemoveCurrent`) is **entirely unused** — no handler,
  router, or other package calls into it (`grep -rn "gcsdeploy\."` across the
  repo only matches its own file). It is dead code left over from the
  pre-GitHub-Actions deploy mechanism (see Prior art). Do not assume it is
  wired to anything; do not extend it expecting a caller to exist.
- No database. `go.mod` has no SQL/Firestore/Redis client — the only
  persistence primitive available anywhere in this codebase is the existing
  `*storage.Client` (GCS), already injected into `DeployHandler` and used
  today only for listing app names (`ServeAppsList`). Any "recent
  deployments" record — if not sourced live from GitHub — would have to be
  written to GCS as new objects, or held in server memory (lost on restart /
  not shared across replicas — unknown replica count, not documented in this
  repo).

## Prior art

- **The deploy mechanism was previously synchronous and DID expose outcome
  directly** — this is the key historical fact. Commit `3c27b99`
  ("[FDEV-165] create app deploy process (#13)") replaced a design where
  `POST /deploy` took `{app, action: "deploy"|"undeploy"|"rollback"}` and
  called `gcsdeploy.PromoteDraftToCurrent` / `RollbackPreviousToCurrent`
  directly in the request handler — meaning success/failure was known and
  returned synchronously in the HTTP response. That commit swapped this for
  the current fire-and-forget GitHub Actions `workflow_dispatch` call
  specifically to move the deploy work into GitHub Actions (out of process,
  per-app repo), which is *why* the outcome-visibility gap in this spec now
  exists — it's a side effect of that migration, not an oversight in the
  original design.
- `79e014e` ("[FDEV-386] Create input for initial deploy (#28)") added the
  bootstrap-deploy UI (first-time deploy input) — most recent deploy-page UI
  change, same file layout the planner will be touching.
  `5b4bf70` ("Consolidate ten RequireAuthCheckers into one shared instance
  (#63)") is the most recent structural change to how handlers are
  constructed/shared — relevant if the planner adds a new handler for
  sidebar data (should share the existing `authChecker` instance, not
  construct a new one).
- No prior attempt at outcome-polling or a sidebar exists in git history for
  this repo.

## Open questions

1. **Can a specific triggered run be identified after dispatch?** GitHub's
   `workflow_dispatch` API returns no run ID. The only way to observe outcome
   is to call `GET
   /repos/{owner}/{repo}/actions/workflows/publish-to-gcs.yml/runs` (or
   `.../runs?event=workflow_dispatch`) after dispatching and take the most
   recent run for that repo, then poll `status`/`conclusion` on it (or on
   `GET .../actions/runs/{run_id}`). This is a heuristic match (most-recent by
   creation time), not a guaranteed-correct correlation — there's a race if
   the same app is deployed twice in quick succession. Planner must decide if
   this heuristic is acceptable for AC #1, and how the frontend would poll
   (new endpoint needed; none exists).
2. **The workflow YAML (`publish-to-gcs.yml`) lives in each
   `Handshake-Learn-Apps/<app>` repo, not this one** — this investigation
   cannot see its steps/job structure, only that it's dispatched with
   `environment` as its sole input. Confirming that its `conclusion` field
   truly reflects "the deployment succeeded" (vs., say, tests-then-a-no-op)
   is not verifiable from this repo alone.
3. **"User who initiated" cannot come from GitHub.** The workflow is
   dispatched using a GitHub App installation token
   (`internal/githubactions/auth.go`), so GitHub records the **App/bot**
   identity as the run's actor, not the human who clicked Deploy in
   learn-apps. The only source for the real user is this app's own request at
   dispatch time: `Hs-Current-User-Id` / `Hs-Logged-In-User-Id` headers are
   present on inbound requests (session-service injects them via
   emissary-ingress — confirmed in `internal/authproxy/authproxy.go:11-16`
   and its tests) but today nothing in `deploy.go` reads them, and they carry
   only a numeric ID, not a name/email. Getting a human-readable identity
   would require either a new GraphQL call (pattern exists:
   `current_user_profile.go`'s `currentUserProfile` query returns
   `name`/`email`) at dispatch time, or accepting the numeric ID. Planner
   must decide, and this only works if the app is captured **at dispatch
   time** and stored somewhere (see #4) — it cannot be recovered afterward
   from GitHub.
4. **Where does "recent deployments" data live?** No database exists. Options
   the planner must choose between: (a) query GitHub's runs-list API live on
   each page load (gives timestamp + GitHub actor, i.e. the bot identity, not
   the human, and no subdomain unless inferred from which per-app repo — one
   API call per app, or one call per repo if scoped to a single app); (b)
   have `ServeDeployAPI` write a small record (app, timestamp, user ID) to
   GCS at dispatch time, then have the sidebar read recent objects from
   there, giving accurate human-user + timestamp but no GitHub-verified
   outcome; (c) some combination — write locally at dispatch, then patch in
   outcome once/if resolved via (a). This directly decides whether AC #2/#3
   need new storage.
5. **Layout**: the deploy page is centered at `max-width: 50rem` with no
   existing sidebar slot (`web/static/css/deploy.css:4-22`). Planner needs to
   decide how much the page widens and whether the sidebar is part of the
   existing `.deploy-main` flex row or a separate top-level layout change.
6. Given #1–#4, the spec's own "if possible" / "if it's possible" framing is
   likely to bind hard on AC #1 (real-time outcome) and AC #3 (real
   human-identified user) — this investigation cannot say whether polling
   GitHub is acceptable to the requester as "showing outcome," and that's a
   product call, not a technical one.
