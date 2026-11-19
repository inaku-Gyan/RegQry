# Issue tracker: Local Markdown

Issues and specs live as Markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`.
- Specs live at `.scratch/<feature-slug>/spec.md`.
- Implementation tickets live at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`, one file per ticket.
- For triaged issues, record a `Status:` line near the top; see [triage-labels.md](triage-labels.md) for values.
- Append conversation history under `## Comments`.

## Publishing and reading

When a skill says "publish to the issue tracker", create the spec or ticket at the corresponding path above, creating directories as needed.

When a skill says "fetch the relevant ticket", read the referenced file. Resolve a bare issue number within its feature directory; ask for the feature if ambiguous.

## Wayfinding operations

Used by `/wayfinder`:

- Map: `.scratch/<effort>/map.md`, containing Notes, Decisions-so-far, and Fog.
- Child ticket: `.scratch/<effort>/issues/<NN>-<slug>.md`. Record `Type:` as `research`, `prototype`, `grilling`, or `task`, and `Status:` as `open`, `claimed`, or `resolved`.
- Blocking: record `Blocked by: NN, NN` near the top. A ticket is unblocked when all listed tickets are resolved.
- Frontier: choose the lowest-numbered open, unblocked, unclaimed ticket.
- Claim: save `Status: claimed` before starting work.
- Resolve: append the result under `## Answer`, save `Status: resolved`, then add a gist and relative link to the map's Decisions-so-far.
