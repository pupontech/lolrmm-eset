# LOLRMM to ESET: quick-rule POC

**Current scope: a small, experimental append-only HIPS POC. Live ESET acceptance has NOT passed.**

The immediate goal is a chosen list of exact executable paths -> preview -> confirmed append -> verify -> exit. No catalog synchronizer, GUI, background process, database or removal engine is being built yet. ESET would perform enforcement; this adds no antivirus signatures.

## Start here

The current candidate is [poc/quick-rules](poc/quick-rules/README.md). A Windows CI test ZIP includes a self-contained harmless `LolrmmEsetTest.exe`, the PowerShell script, launcher and exact-path CSV. It is for the owner's isolated ESET test machine only, not production or a certified release.

- Double-click `START-HERE.bat` for non-mutating live Preview.
- Run `START-HERE.bat -Apply` only for the explicitly confirmed isolated-machine experiment.
- Run `START-HERE.bat -ValidateOnly` for package validation with no ESET access.

Use the ZIP, not this source checkout, for the packaged test: the source tree intentionally does not commit the built EXE. Do not change `rules.csv` to target real RMM tools before the harmless import/block/log/unblock test passes. Exact paths do not cover renamed or relocated executables.

## Current evidence and limitations

- Phase 0 research is complete.
- Public native XML exists: ESET's official accessibility sample demonstrates a small HIPS collection with APPEND=1; a community consumer 15.0.18 export supplies candidate block/start-operation fields. Neither establishes current-build compatibility.
- The quick POC targets only consumer major 19 for an explicit unvalidated test. Unknown products/versions/shapes are refused.
- Hosted Windows tests can prove script, fixture and package behavior, not native ESET import/enforcement. Actual signing, append preservation, identifier handling, duplicate prevention and block/log/unblock must be demonstrated by the owner.
- No agents install ESET, provision VMs or mutate live configurations. No public licensed release is created; the license remains unselected.

The older [guided observation kit](poc/automated/README.md) is preserved for historical/reference use, not the quick-injection entrypoint.

## Design and verification

- [Current narrowed POC decision](docs/decisions/0002-small-append-poc.md)
- [Owner-run environment decision](docs/decisions/0001-project-scope-and-gates.md)
- [Original full application brief](docs/PROJECT_BRIEF.md) - downstream scope deferred
- [Phase roadmap](docs/roadmap.md)
- [Native XML evidence record](docs/eset-hips-xml.md)
- [Testing record](docs/testing.md)
- [Agent instructions](AGENTS.md)

Run the dependency-free quick-rule tests with Windows PowerShell 5.1 or PowerShell 7:

```text
powershell.exe -NoProfile -File poc\quick-rules\tests\Test-QuickRules.ps1
pwsh -NoProfile -File poc/quick-rules/tests/Test-QuickRules.ps1
```

Windows CI builds and verifies the exact-source test ZIP. Only tests actually recorded in `docs/testing.md` are claimed as executed. Live ESET compatibility and the downstream app remain gated.

LOLRMM and ESET do not endorse this project. RMM software can be legitimate; blocking it can disrupt authorized support.
