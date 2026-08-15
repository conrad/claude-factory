# Failure report — attempt {{N}}

- **When:** {{ISO timestamp}}
- **Stage:** {{verify | review:correctness | review:design | review:tests | security | conformance | gate2-revise}}
- **Run:** {{run-id}}

## What failed

{{One sentence. For verify: the step and exit code. For a review refutation:
the concrete failure scenario (inputs/state → wrong behavior). For
conformance: the drift found.}}

## Evidence

```
{{Test output, the refuting scenario, or the offending diff hunks.}}
```

## Suspected cause

{{Best hypothesis — points the builder at the area, doesn't prescribe the fix.}}

## Required before retry

{{For review refutations: the failing test that encodes this scenario, added
to the suite (DESIGN.md §5). For verify failures: none.}}
