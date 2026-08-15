# Agent role definitions

One file per agent node (DESIGN.md §3), written in Phase 1 (investigator,
planner, builder, integrator) and Phase 2 (triage, test-writer, reviewer,
security, conformance, documenter).

Each definition states: model tier (from factory.config.yaml), inputs read
from the run directory, the output file it must write, and its contract —
including what it is *not* allowed to do (e.g., the investigator never
proposes solutions; the builder never modifies test assertions).
