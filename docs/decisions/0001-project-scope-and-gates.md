# ADR 0001 — Project scope, execution gates, and unresolved environment conflict

- **Status:** Accepted for repository setup; test-environment resolution pending owner decision.
- **Date:** 2026-10-07

## Context

The project brief requires a Windows VM with a current consumer ESET installation for the HIPS XML round-trip POC and full enforcement validation. The owner's standing project workflow says agents verify on GitHub Actions Windows runners, then deliver a Windows deploy ZIP for owner live testing; agents do not provision VMs or install live software.

The project also requires an open-source license but does not name one. Creating a `LICENSE` file would grant specific rights and should not be guessed.

## Decisions

1. Repository and product scope are consumer ESET only; no enterprise/managed ESET products.
2. The ESET native HIPS/eCMD configuration round-trip and actual block test is a mandatory architecture gate before the full app.
3. No Phase 0 or implementation work starts until the owner explicitly starts the project.
4. No agent-provisioned VM or live ESET installation/configuration mutation is allowed under the standing delivery policy. Before Phase 1, the owner must choose/provide a safe ESET test environment or explicitly revise that policy. GitHub Windows CI is required but does not by itself prove ESET enforcement.
5. No license is chosen during setup. Select an open-source license before distribution; until then, no `LICENSE` file or release is created.
6. GitHub Issues are enabled; Hermes Kanban is the execution board and holds the phase dependency graph. No GitHub Project board is created because the current GitHub token lacks the `read:project` scope; do not request broader auth just for setup unless the owner later asks for a GitHub Projects board.

## Consequences

- Phase 1 remains gated until the test-environment conflict is resolved.
- Research must not claim undocumented behavior as verified.
- A release cannot be considered open-source/distributable until a license is selected and added.
- Local project setup can be completed without research, application code, or ESET mutation.
