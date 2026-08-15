# Plan — {{title}}

- **Run:** {{run-id}}
- **Revision:** {{0}}
- **Based on:** investigation.md

## Approach

{{One paragraph: the chosen approach and why, over what alternative.}}

## Steps

1. {{Numbered, concrete steps. Each names the files it touches.}}

## Files to touch

- `{{path}}` — {{what changes}}

## Interfaces

{{New/changed signatures, schemas, endpoints — exact shapes.}}

## Test strategy

{{What the test-writer will write, per acceptance criterion. Each test must
fail before the build and pass after. This section is the test-writer's spec.}}

## Risks & rollback

- {{Risk}} → {{mitigation}}
- Rollback: {{how to revert safely}}

## Out of scope

{{Explicit list. The conformance checker flags anything in the diff that
serves none of the steps above, and anything listed here that appears.}}

## ADR

{{If an architectural choice was made: draft ADR here (see templates/adr.md),
finalized by the documenter. Otherwise "none".}}
