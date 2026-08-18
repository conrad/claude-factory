# Spec — Show deployment outcome + recent-deployments sidebar on the deploy page

- **Run:** 2026-08-15-deploy-status-feedback
- **Source:** prompt
- **Repo:** learn-apps

## Request

When a user clicks to deploy, they can see whether the request to start the
action/workflow was successful, but they never get to see whether the deployment
action succeeded. Let's add that here. If it's possible, show on the deploy page
a list of the most recent deployments in a right sidebar. If possible, list the
app/subdomain, the date and time, and the user who made the deployment.

## Acceptance criteria

<!-- DRAFT — inferred from the request; planner to confirm against investigation. -->

1. **DRAFT** — After a user triggers a deploy, the deploy page reflects the
   *outcome* of the deployment action (succeeded / failed / in-progress), not
   just that the start request was accepted.
2. **DRAFT** — The deploy page shows a right-hand sidebar listing the most
   recent deployments.
3. **DRAFT** — Each deployment entry lists, where the data is available: the
   app/subdomain deployed, the date and time, and the user who initiated it.
4. **DRAFT** — Scope is bounded by what the underlying deploy mechanism
   (GitHub Actions workflow / action) actually exposes; capabilities that the
   backend cannot observe are called out rather than faked. ("If it's possible"
   / "If possible" in the request is explicit permission to scope down where the
   data or API does not support a piece.)

## Context / links

- Deploy flow appears to run through a GitHub Actions workflow/action (see repo
  `githubactions` package). Investigation to confirm where deploy status and
  actor/timestamp/subdomain metadata are available.
