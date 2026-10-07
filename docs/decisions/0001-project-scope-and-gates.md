# ADR 0001 — Project scope and execution gates

- **Status:** Accepted; owner-run ESET POC environment selected, evidence pending.
- **Date:** 2026-10-07

## Context

The project brief requires an isolated Windows/ESET environment for the HIPS XML round-trip POC and full enforcement validation. The owner's standing project workflow says agents verify on GitHub Actions Windows runners, then deliver a Windows deploy ZIP for owner live testing; agents do not provision VMs or install live software. On 2026-10-07, the owner selected the owner-run route: the owner will run the POC on their isolated Windows/ESET test machine or VM; the agent prepares the POC package and steps.

The project also requires an open-source license but does not name one. Creating a `LICENSE` file would grant specific rights and should not be guessed.

## Decisions

1. Repository and product scope are consumer ESET only; no enterprise/managed ESET products.
2. The ESET native HIPS/eCMD configuration round-trip and actual block test is a mandatory architecture gate before the full app.
3. No Phase 0 or implementation work starts until the owner explicitly starts the project.
4. The owner runs Phase 1 on their isolated Windows/ESET test machine or VM. The agent must not provision a VM or install/mutate live ESET. Prepare the POC kit and instructions, then wait for the owner to run it and return only sanitized rule XML excerpts and results needed for analysis. Do not request or accept an ESET password or a full unsanitized configuration export in chat or the public repository. GitHub Windows CI is required but does not by itself prove ESET enforcement.
5. No license is chosen during setup. Select an open-source license before distribution; until then, no `LICENSE` file or release is created.
6. GitHub Issues are enabled; Hermes Kanban is the execution board and holds the phase dependency graph. No GitHub Project board is created because the current GitHub token lacks the `read:project` scope; do not request broader auth just for setup unless the owner later asks for a GitHub Projects board.

## Consequences

- Phase 1 may begin after Phase 0 is accepted; its actual ESET import/block/unblock proof remains owner-run and blocks Phase 2 until evidence is returned and verified.
- Research must not claim undocumented behavior as verified.
- A release cannot be considered open-source/distributable until a license is selected and added.
- Local project setup can be completed without research, application code, or ESET mutation.
