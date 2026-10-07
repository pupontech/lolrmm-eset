# Project status

**Phase 0 research and independent review complete; Phase 1 POC kit is queued.** The project brief, decision record, phase roadmap, public GitHub repository, Hermes project, and Kanban board are set up. No application code, HIPS XML fixture, or ESET configuration mutation has been performed.

## Current gates

- Phase 0: `docs/research.md` citation/evidence verification passes; Luna fresh-eyes review `t_9b67021c` is complete and reconciled. Phase 0 Kanban card `t_7811fe5e` is ready to close.
- Phase 1: owner selected an isolated owner-run Windows/ESET test machine or VM. POC app and owner guide tasks are staged behind the owner gate; the owner performs live ESET tests. Do not provision a VM or mutate live ESET as an agent.
- License: not selected; choose before distribution.
- GitHub Project board: not created because the current token does not have the `read:project` scope. Hermes Kanban is the execution board; GitHub Issues remain enabled.

## Canonical locations

- Local checkout: `/root/Projects/lolrmm-eset/main`
- GitHub repository: `https://github.com/pupontech/lolrmm-eset`
- Hermes project/board: `lolrmm-eset`
- Owner-start gate: `t_e1c7af20` (done).
- Phase 0 review: `t_9b67021c`; owner-run ESET environment decision: recorded in ADR 0001.
