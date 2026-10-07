# ESET HIPS proof of concept — not started

The POC is the Phase 1 go/no-go gate. This directory intentionally contains no executable POC code yet.

Do not build the full application or GUI until Phase 1 proves the complete supported flow on an owner-approved, isolated ESET consumer test environment:

`C# → export current config → preserve baseline → programmatically add one harmless HIPS block rule → validate → official signing if required → ecmd import → fresh export/verify → test executable blocked and logged → remove app-owned rule → executable runs again`

Preserve unrelated HIPS rules and other ESET configuration. Capture sanitized fixtures/evidence in `docs/eset-hips-xml.md`; never commit credentials or sensitive exported settings. If any required step fails, stop and document the failure; do not continue to Phase 2.

The environment conflict is recorded in `docs/decisions/0001-project-scope-and-gates.md`. The agent must not provision a VM or install/mutate live ESET without explicit resolution/authorization from the owner.
