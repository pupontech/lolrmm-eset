# Roadmap and phase gates

**No phase is active.** This plan is staged in Kanban, unassigned, and must not dispatch until the owner explicitly starts Phase 0. Every phase is sequential; do not skip or parallelize across a gate.

| Phase | Deliverable | Exit gate |
|---|---|---|
| 0 — Research | `docs/research.md`, official current ESET and LOLRMM findings, direct sources and unresolved questions | Owner accepts documented evidence and decides how to satisfy the real ESET POC environment without violating the no-agent-VM/live-install policy. |
| 1 — ESET HIPS POC | Minimal C# POC under `poc/`, sanitized real-version fixtures, `docs/eset-hips-xml.md` | Programmatic export/merge/sign/import/re-export round trip succeeds; harmless executable is blocked and logged by ESET; managed rule is removable; unrelated configuration survives. If any part fails, stop. No downstream app work. |
| 2 — ESET configuration library | Detection, version adapter, export/parse/rule ownership, signer, import, verify, backups | Unit tests against sanitized captured XML and explicit version support; unknown versions read-only. |
| 3 — LOLRMM pipeline | HTTPS client, cache, defensive parser/normalizer, internal model, persistent selections | Unit tests cover schema evolution, malformed records, defaults, overrides, cache fallback. |
| 4 — Safe rule compiler | Indicator selection, safety validation, HIPS rule compilation | Tests prove no broad/unsafe targets, generic Windows process denylist, truthful compatibility classifications. |
| 5 — Desired/current diff | Idempotent ADD/UPDATE/REMOVE/UNCHANGED, shared Preview/Apply plan, transactional orchestration | Tests prove only app-owned rules change, no duplicates, failures fail closed, backups and verification are required. |
| 6 — Minimal GUI | Native Windows checklist, search, selection controls, preview, apply/status | UI calls higher-level services only; user can review/change choices; no apply on refresh. |
| 7 — Windows integration | GitHub Actions Windows verification plus owner-controlled live ESET evidence; `docs/testing.md` | Actual product/version flow, block/log/unblock, unrelated-rule preservation, rollback, AnyDesk/TeamViewer, repeat apply and failure cases recorded. |
| 8 — Packaging and docs | x64 distributable, README, license, build/release instructions | Owner-approved license and release; exact source SHA, hosted Windows checks, artifact bytes/hash, and owner acceptance verified. |

## Owner gates and unresolved decisions

1. **Start gate:** explicitly authorize Phase 0. Setup request alone does not authorize it.
2. **Test-environment gate:** before Phase 1, resolve the brief's request for an agent-created Windows VM versus the owner's standing policy that agents do not provision VMs/install live software. Preferred route is owner-provided/owner-run ESET test environment with hosted Windows CI for non-live tests; record the owner's actual choice before mutation.
3. **Release gate:** select an open-source license before distribution. Do not guess one during setup.
4. **Compatibility gate:** support only ESET consumer versions actually documented and validated; unknown major versions stay read-only.

## Development and release evidence

Use GitHub Actions Windows runners for code that can be tested in CI. The owner performs live ESET acceptance on Windows. Keep those evidence classes separate; CI success is not proof of HIPS enforcement. Do not provision a VM or install ESET on a live machine as an agent. Build/release only after the applicable phase gate is accepted, and ship a deployable Windows artifact for owner testing.
