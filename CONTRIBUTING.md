# Contributing

This repository is currently planning-only. Do not begin Phase 0 or implementation unless the owner has explicitly authorized it and the corresponding Kanban gate is open.

## Before changes

1. Read `AGENTS.md`, `docs/PROJECT_BRIEF.md`, `docs/roadmap.md`, and the applicable decision records.
2. Confirm the assigned Kanban task is authorized, unblocked, and has exact file ownership and acceptance checks.
3. Preserve unrelated working-tree changes. Never use destructive Git cleanup/reset/checkout/stash commands to make a tree appear clean.
4. Do not modify ESET configurations except for an explicitly authorized Phase 1/7 test in the owner-approved environment.

## Verification and evidence

Use focused tests plus the full applicable test suite. Windows-only behavior must run on GitHub Actions Windows runners; owner live ESET testing remains a separate acceptance class. Report exact commands and results, and label missing/skipped/live-only evidence honestly. Do not claim ESET compatibility or enforcement without a verified product/version result.

## Pull requests

Keep changes scoped, test them, explain safety implications, list evidence, and update relevant docs. Do not publish a release or choose the project license without owner approval. Changes to ESET XML handling, rule safety, signing, backups, or import behavior require fresh-eyes review and regression tests.
