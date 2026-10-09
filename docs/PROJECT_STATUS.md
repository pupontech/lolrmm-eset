# Project status

Phase 0 research is complete. Phase 1 has a historical observation kit, online native XML evidence, and the current small append-only POC implementation. **The native ESET architecture gate is NOT passed.**

## Current branch and scope

- Repository: https://github.com/pupontech/lolrmm-eset
- Integration branch: `feat/quick-append-poc`
- Local worktree: `/root/Projects/lolrmm-eset/quick-append-poc`
- Current authorization: [ADR 0002](decisions/0002-small-append-poc.md)
- Current entrypoint: `poc/quick-rules/START-HERE.bat`
- Original guided kit preserved: `poc/automated/`

The directory called `main` is an older owner-kit worktree, not the authoritative current integration branch. Use Git refs/remotes and embedded full-SHA provenance rather than directory names to establish authority.

## Gates

- Code/fixture/Windows/package evidence: record actual runs in `docs/testing.md`; no test should be assumed passed from this status page.
- Owner-live: required consumer-build signing/import/readback, preservation, harmless block + HIPS log, targeted manual removal/unblock, unchanged-input no duplicates.
- Agents do not provision VMs, install ESET or mutate live ESET. The owner runs the isolated-machine experiment.
- Full catalog/GUI/application remains deferred until native Phase 1 acceptance.
- License remains unselected. No licensed production release, tag or main merge is authorized by the POC.

Known scope limits: no automatic removals, no whole-backup automatic rollback, no wildcard/hash/signer/domain enforcement, and no promise to cover relocated or renamed executables. ESET itself performs any eventual enforcement after the utility exits.
