# Domain docs

## Before exploring

- Read the root `GLOSSARY.md` if it exists.
- Read ADRs under `docs/adr/` that concern the work.

If these files are absent, proceed silently. The `/domain-modeling` skill creates them when terminology or decisions are resolved.

## Layout

This repo uses a single-context layout:

- `GLOSSARY.md`: shared domain vocabulary.
- `docs/adr/`: architectural decision records.

## Vocabulary

Use glossary terms when naming domain concepts in issues, proposals, hypotheses, and tests.

If a needed term is missing, reconsider whether it belongs to the domain or note the gap for `/domain-modeling`.

## Decision conflicts

When a proposal contradicts an existing ADR, identify the ADR and explain why the decision should be revisited.
