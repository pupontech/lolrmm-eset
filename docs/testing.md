# Testing and acceptance evidence

The Quick Rules POC has automated and hosted Windows evidence. Native consumer ESET import/enforcement remains OWNER_PENDING; no ESET was installed or configured by an agent.

## Verified implementation snapshot

- Source: `caf154dbbceee1102414be039a4558804d00304a`, branch `feat/quick-append-poc`.
- Hosted run: https://github.com/pupontech/lolrmm-eset/actions/runs/37909259755
- Both required matrix jobs, Windows 2022 and Windows 2025, completed successfully.
- Source/Actions test artifacts only. No release, tag or main merge.

| Evidence class | Result | Scope and limitations |
|---|---|---|
| Local PowerShell 7 / Linux | PASS | Main suite: 13 tests, 0 failures, 91 assertions; boundary, regression, signature, version and real-subprocess checks also pass. No Windows/ESET claim. |
| Windows PowerShell 5.1 and PowerShell 7, both hosted runners | PASS | Main suite has 13 tests / 91 assertions per engine; additional boundary/regression/signature/version/process checks pass. Transactions use synthetic providers, not installed ESET. |
| Official native XmlSignTool | PASS | Valid ESET Authenticode; actual official binary signed public vendor XML and a generated synthetic append candidate. The production content validator accepted both. CI uses synthetic input in a private console, never an owner password. No import. |
| Immutable package and actual launcher | PASS | Exact member allowlist, complete member hash manifest and full source SHA; extracted BAT works from a space-containing folder, ValidateOnly exits 0, missing script exits 1, self-contained EXE prints Test Application. No ESET access. |
| Downloaded Actions ZIPs | PASS | Parent verified both archives, sidecars, member hashes, provenance and source files against the exact Git commit with the Windows checkout CRLF transformation. |
| Owner-controlled consumer ESET | PENDING | Exact Windows/ESET versions, interactive real-password signing, import, HIPS semantics, preservation, no duplicates, block/log/unblock remain unproved. |

## Artifact integrity

Artifact names in the run are `QuickRules-windows-2022` and `QuickRules-windows-2025`. Each contains `LOLRMM-ESET-QuickRules-0.1.0-poc.1.zip` and its relative-name `.sha256` sidecar. The outer ZIP hashes can differ because the runners package independently.

- Windows 2022 ZIP SHA-256: `734d3f2e5e48736242004401345cf5417d36449eb2ce026a8127dcd9f2aa6f0e`.
- Windows 2025 ZIP SHA-256: `dc22fcd23c7aff3841c88202a2cb0a0f59a81036e536820daefb1079c85489bc`.

Select the Windows 2022 artifact for the owner test; preserve its bytes. The built EXE is intentionally not committed. Public/synthetic signer fixtures are separate `NativeSigner-*` artifacts and are not configurations to import.

## Review and corrections

An independent Luna defect review found wrong successful launcher exit propagation, case-only path rerun collisions, a mutable signed-payload interval, and missing signer workflow coverage. Parent reproduced and fixed these. Additional boundary probes caught significant-whitespace loss, a post-apply PowerShell expression error, and descendant-held output reads exceeding the deadline; regressions now pass. Windows-native execution exposed redirected-stdin signer incompatibility and cmd argument transformation in the package test; the corrected paths are covered by the successful hosted run above.

Signed-payload checks allow only the exact trailing signature-comment representation actually observed from the official tool. Follow-up independent review confirmed the original findings closed and identified one low-severity absolute-regex-anchor mismatch: an internal trailing LF was accepted. A focused test reproduced it, then absolute anchors and fixed-length extraction corrected it in `0.1.0-poc.2`; the local signature suite passes against the genuine signed public fixture. This follow-up must pass a fresh exact-source hosted run before delivery; the hashes above refer only to the earlier immutable `.1` snapshot.

The content checks do not verify cryptography themselves: ESET's import interface must validate the signature. Existing XML comments, leaf values and configuration ordering are not discarded.

Process deadlines do not certify termination of every descendant or ESET service-side operation. Failures warn of unknown outcomes and prohibit a success claim; inspect ESET before retrying. The owner-live gate is not replaced by hosted tests.

## Required current POC owner test

Follow [the package instructions](../poc/quick-rules/README.md) on an isolated Windows client with consumer ESET major 19. Keep the bundled CSV unchanged for this first test.

- [ ] Record exact Windows/ESET versions; verify supported consumer metadata and matching exported version.
- [ ] Run the harmless EXE normally before injection: Test Application, exit 0.
- [ ] Preview and inspect the exact target/name; confirm HIPS and password-authorized ESET CMD manually.
- [ ] Explicitly authorize Apply; enter the setup password only at the official native signer's console.
- [ ] Import and readback verify the exact new rule and unrelated configuration.
- [ ] Run the EXE NON-ELEVATED; prove ESET blocking with the matching denied HIPS event, rule/path/time and notification behavior.
- [ ] Repeat Apply with unchanged input: no duplicate and no sign/import.
- [ ] Remove ONLY the exact new test rule manually; run the EXE normally again: Test Application, exit 0.
- [ ] Confirm unrelated administrator rules/settings remain intact.

Raw exports and diagnostics stay private. A command exit 0 or successful readback alone is not enforcement evidence. No automatic rollback is provided.

## Deferred full-application scenarios

Catalog/offline-feed handling, AnyDesk/TeamViewer selections, automatic managed-rule removal, backup rotation/restore and GUI acceptance belong to downstream phases. They are intentionally not implemented in the append-only POC. The original Definition of Done is not complete until owner-live native acceptance and the later explicitly authorized phases pass.
