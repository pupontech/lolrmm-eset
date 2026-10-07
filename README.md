# LOLRMM → ESET

**Status: project setup only — research and implementation have not started.**

A planned open-source Windows utility to let a user review the public LOLRMM catalog, choose which RMM products should be blocked, and synchronize suitable indicators into native rules in locally installed consumer ESET HIPS.

The intended flow is:

> Open → review/search the RMM list → choose what to block → preview → apply to ESET → close.

ESET itself would enforce the rules. This application is not intended to remain running and does not create custom antivirus signatures.

## Current project status

- Project brief, agent instructions, phase plan, local workspace, public GitHub repository, and Hermes Kanban tracking are set up.
- Phase 0 research has **not** started. No ESET behavior is yet verified, no HIPS XML fixture exists, and no compatibility claims are made.
- Phase 1's ESET configuration round-trip and enforcement POC is a hard gate. Full application development must not begin unless that POC passes.
- A test-environment policy conflict is recorded in [ADR 0001](docs/decisions/0001-project-scope-and-gates.md): the source brief asks for an agent-created Windows VM, while the owner's standing workflow is hosted Windows CI plus owner-run live Windows testing. Resolve this before any ESET mutation.

## Intended scope

Consumer ESET Windows products only, with ESET Security Ultimate / ESET HOME Security Ultimate as the primary target. The application will use documented local ESET configuration facilities, primarily HIPS and ESET CMD, only after current official documentation and a real POC verify the behavior. Enterprise products and cloud/managed services are out of scope.

LOLRMM's structured catalog is the canonical list: <https://lolrmm.io/api/rmm_tools.json>. AnyDesk and TeamViewer are planned to default to unselected; other safely representable tools default selected. User choices persist across refreshes. Downloading a new catalog never applies rules automatically.

## Project documents

- [Full project brief](docs/PROJECT_BRIEF.md)
- [Phase plan and gates](docs/roadmap.md)
- [Research record](docs/research.md) — pending Phase 0
- [ESET HIPS XML / POC evidence](docs/eset-hips-xml.md) — pending Phase 1
- [Testing record](docs/testing.md) — pending implementation and owner validation
- [Project decisions](docs/decisions/)
- [Agent instructions](AGENTS.md)

## Planned implementation and testing

The preferred stack is C# on a current supported .NET version and a native Windows GUI (WPF is the default unless research justifies otherwise). The exact framework/version, ESET product/version support, configuration format, signing behavior, and HIPS matching semantics remain research questions. No build or installation instructions are claimed yet.

The project will require unit tests, GitHub Actions Windows-runner verification, and owner-performed live ESET acceptance before a release can be called complete. No license has been selected yet; choose one before publishing a distributable release. LOLRMM and ESET are not project endorsers; their marks belong to their respective owners.
