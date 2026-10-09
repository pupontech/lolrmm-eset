# ADR 0002: small append-only Phase 1 POC

Status: Accepted for implementation and owner-run testing; NOT accepted as ESET compatibility or production readiness.

## Authorization and boundaries

The owner requested simplifying the project to quickly inject a chosen set of rules, asked for online schema evidence, then explicitly directed continuing the project. Continue Phase 1 as a small Windows PowerShell 5.1 POC, not the planned full catalog/GUI application. Prepare isolated-owner-machine Apply, hosted Windows tests and a test ZIP. Do not install or mutate live ESET as an agent. Do not release/tag/merge the full application. Preserve the existing observation kit and unrelated worktrees.

## Product shape

One on-demand script plus exact-path CSV and a small batch launcher. Default Preview is non-mutating. No catalog download, GUI, persistent database, supervisor, polling, scheduled tasks or services. Apply is append-only; input omissions never cause removals. Same desired rules should be a no-op. Name collisions/different targets under the same owned name fail, never replace administrator rules. Only exact `LOLRMM Block - ` names are generated, with deterministic path-derived suffixes.

## Evidence and experimental import

ESET KB7375's public consumer sample uses ITEM/NODE HIPS configuration under plugins/01000001/settings/rules with APPEND=1. A downloaded community consumer 15.0.18 export supplies enabled=1, action=2, priority=80, severity=3 and peOperations/Application_Create=1 on named deny-child-process rules. All-sources/exact-target composition is an explicitly experimental adaptation, not owner-live validated ESET 19 support.

Live Apply is restricted to consumer product major 19 and must require BOTH an isolated-machine acknowledgment and visible typed confirmation naming the unvalidated append experiment, AFTER showing the exact generated names/paths. Unknown product/shape, unsafe path or readiness refusal stops before import. Detect the exact installed product/version independently from the export and require a matching home export. Default-preview never creates/imports rules. Fixture tests are not evidence of native matching or append semantics.

## Apply transaction

Validate paths and known consumer metadata -> private local run directory -> fresh export and untouched before backup -> inspect current rule inventory and calculate ADD/UNCHANGED only -> generate minimal HIPS APPEND payload -> visible owner confirmation -> official XmlSignTool interactive signing (no password capture or transcript) -> fresh export/concurrency check -> documented ecmd import -> fresh export and verify exact requested fields/targets plus preexisting rules and unrelated settings.

Use validated ESET-signed ecmd and signer; arguments never include passwords. Signing/import nonzero, timeouts or readback mismatch fail; never claim rollback or successful enforcement. Preserve raw private evidence, provide a compact no-raw-value result and explicit manual test-rule cleanup instructions. Do not auto-restore the full backup. No broad volatile stripping is permitted; if incidental settings churn prevents preservation verification, report it as unverified instead of suppressing the difference.

For the first owner test use only LolrmmEsetTest.exe, not actual RMM products or system components. Require normal-user baseline launch, append/import/readback, normal-user blocked launch with matching HIPS log, owner removal of only the exact test rule, normal-user launch again, and an identical-input no-duplicate rerun. Removals remain manual in this POC.

## Delivery gate

The original guided kit is historical evidence tooling, not the primary workflow. New code and extracted package must pass Windows 2022 and 2025 on Windows PowerShell 5.1; PowerShell 7/Linux tests remain supplemental. Publish only a source/Actions test artifact, no licensed public release. Owner-live Phase 1 remains the gate before the downstream application.
