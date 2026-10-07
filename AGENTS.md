# Agent instructions — LOLRMM → ESET

## Project state and start gate

This repository is **planning/setup only**. There is no implementation yet. Do not begin research, coding, VM provisioning, ESET installation/configuration, catalog downloads, or ESET mutation until the owner explicitly starts Phase 0. The Kanban root card is the authoritative owner gate; all phase cards must remain unassigned and dependency-gated until then. A request to set up the project is not authorization to start its phases.

Read `docs/PROJECT_BRIEF.md`, `docs/roadmap.md`, and `docs/decisions/0001-project-scope-and-gates.md` before work. Treat the brief as the product contract. If requirements conflict or safety is uncertain, fail closed and record the uncertainty; never invent ESET XML or command behavior.

## Non-negotiable scope

- Consumer ESET Windows products only; primary intended target ESET Security Ultimate / ESET HOME Security Ultimate. No ESET PROTECT, Inspect, EDR, Endpoint Security, business licensing, MSP, cloud, or enterprise APIs.
- ESET HIPS is the enforcement engine. Do not claim custom AV signatures. Do not create antivirus exclusions, HIPS allow rules, firewall rules, or domain blocks in v1.
- No background service, driver, scheduled task, tray daemon, server, telemetry, or automatic apply. The app exits after the user applies; ESET performs ongoing enforcement.
- Use documented ESET local configuration interfaces only (`ecmd.exe`, and official `XmlSignTool` when required). Never edit protected registry/database/internal files, inject, patch, disable Self-Defense, stop services, or automate GUI clicks as the main integration.
- Never assume HIPS XML, path/wildcard matching, commands, or signing behavior. Require current official documentation and a real exported fixture/POC.
- Preserve unrelated ESET configuration and administrator rules. Modify only rules with the exact deterministic `LOLRMM Block - ` ownership prefix.
- Reject broad/unsafe indicators and generic Windows process names. Do not widen rules to improve coverage.
- Do not store or log ESET passwords. Never pass secrets on a command line.

## Required phase order and gates

Follow `docs/roadmap.md` exactly: Phase 0 research → Phase 1 ESET HIPS POC → Phase 2 ESET library → Phase 3 LOLRMM pipeline → Phase 4 safe rule compiler → Phase 5 diff/apply plan → Phase 6 minimal GUI → Phase 7 Windows integration tests → Phase 8 packaging/docs.

**Phase 1 is the architecture gate.** Do not build the full app, GUI, or downstream integration before a real POC demonstrates export → programmatic rule insertion → supported signing → `ecmd` import → re-export verification → harmless executable blocked by ESET and logged → managed rule removed → executable runs again, while unrelated settings/rules remain intact. If any step fails, stop and document the exact failure; do not paper over it.

The original brief requests a newly provisioned Windows VM. The owner's standing delivery policy is different: agents verify on GitHub Actions Windows runners and ship a deploy ZIP for the owner to run on Windows; agents do not provision VMs or install live software. Do not silently resolve this conflict. Phase 0 may document official sources, but before Phase 1 the owner must approve/provide an ESET test environment or explicitly revise that policy. Record the chosen test route before any configuration mutation.

## Working and verification rules

- Keep the solution small and maintainable: C#/.NET Windows desktop, prefer WPF unless Phase 0 gives a current documented reason otherwise; no Electron, web UI, microservices, or unnecessary frameworks.
- Separate LOLRMM client/parser/normalizer, domain models, rule builder/diff/safety, ESET adapters/configuration/commands/signing, storage, and GUI. Button handlers must not manipulate ESET XML.
- Write tests before or with changes. Cover malformed/evolving upstream data, safe indicator selection, defaults/persistence, ownership/diff/idempotency, XML preservation, failures, and unknown versions.
- Verify Windows behavior on GitHub-hosted Windows runners. The owner performs live ESET acceptance on Windows; never claim it was tested without evidence. Separate Linux/unit, hosted-Windows, and owner/live-ESET evidence.
- Before external writes (GitHub issues/settings/releases), verify the exact target and read back the result. Never publish a release without owner authorization and verified acceptance gates.
- Preserve user work. Never run `git clean`, `git reset --hard`, `git checkout .`, or stash to manufacture a clean tree. Do not commit/push unless the active task explicitly authorizes repository setup/integration.
- Kanban tasks must be self-contained, unassigned until work is authorized/routing settled, and carry exact file scope, dependencies, and verification requirements. One writer per file scope; reviewers write separate findings.

## Project artifacts

- Product requirements: `docs/PROJECT_BRIEF.md`
- Ordered milestones: `docs/roadmap.md`
- Current research: `docs/research.md` (intentionally not researched yet)
- POC evidence: `docs/eset-hips-xml.md` and `poc/` (intentionally empty of code until Phase 1)
- Integration test record: `docs/testing.md`
- Project-specific decisions and unresolved conflicts: `docs/decisions/`
