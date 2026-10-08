# LOLRMM / ESET Phase 1 - recreated guided kit

**This is a runnable evidence-preparation kit, not a fully automated blocking utility.** It automates integrity checks, local folders, configuration exports, non-elevated process execution and reports. Creating/removing the exact test rule and confirming its HIPS log entry still require the owner. No ESET configuration import or UI automation is implemented. No consumer product/version is yet certified supported.

## Path handling repair - v2026-10-08.1

The old guard rejected valid forward-slash Windows drive paths and any ordinary folder containing cloud-provider words as a substring. Both failures were reproduced. The new guard accepts Windows separator variants, checks cloud names at directory-component boundaries, preserves configured sync-root/reparse/wildcard protections and identifies the exact failing path role/reason with user details redacted. The actual owner-side rejected path was not supplied, so the precise cause of that particular run remains unknown.

The launcher now validates the complete package before asking for TEST, and prints `PACKAGE_PREFLIGHT_PASS` on success. To check the actual extracted package without ESET access, run:

```powershell
.\Run-EsetHipsPoc.bat -ValidateOnly
```

This must print `VALIDATION_ONLY_PASS` and exit 0. It is a package diagnostic, not a HIPS test. If the guard refuses a genuine cloud/network/reparse location, its error now names that specific reason. Do not disable the guard.

## Start on your isolated Windows machine

1. Extract the complete Windows CI ZIP into a private local, non-synced folder. Do not run inside the ZIP. Use a fresh directory; do not overlay the previous kit.
2. **Double-click `Run-EsetHipsPoc.bat` normally. Do not use Run as administrator.** The controller must stay non-elevated so the test executable has a normal user token.
3. Type `TEST` when asked to confirm this is an isolated test machine. Consent to UAC only when the export worker requests it. Use the same Windows account; credential-based elevation to a different account is rejected.
4. Follow the narrow manual rule prompts. Use only the exact executable path printed by the runner, not the EXE in the extraction folder. Do not widen the target or disable protection.
5. Read the final result and evidence directory. Exit code 2 means guided observations finished but the mandatory programmatic Phase 1 gate is still UNVERIFIED, not an application crash.

Dry run (no export, rule changes or executable launch):

```powershell
.\Run-EsetHipsPoc.bat -DryRun
```

Direct invocation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Launch-Kit.ps1 -IAmOnATestMachine
```

`Launch-Kit.ps1` chooses the newest controller by parsed date and numeric revision; revision 10 sorts after revision 2. The BAT preserves the child's exit code and pauses to keep errors visible. The launcher passes an explicit test-machine acknowledgment only after your typed consent, or when you explicitly provide the switch.

## Architecture and limits

- The normal-user controller verifies every root package member against `SHA256SUMS.txt`, prepares private run/evidence folders and invokes the harmless executable with redirected stdout/stderr and bounded waits.
- A separate UAC export worker uses documented `ecmd.exe /getcfg <path>`. It validates the calling account and ESET executable identity. It does not run the test executable, create rules or import configuration.
- HIPS and ESET CMD readiness are owner-reported until a real, reviewed ESET XML schema establishes those fields. `ekrn` running alone does not prove HIPS is enabled. Disabled/unknown HIPS is a stop condition.
- First the harmless executable must print exactly `Test Application` with exit 0 and empty stderr. Then the owner creates ONE manual rule, the kit captures another export, attempts the same executable normally and asks for the matching HIPS log observation at that attempt's time.
- In cleanup, the owner removes ONLY that exact rule; the kit exports again and checks the executable runs. It never restores the complete baseline blindly, which could overwrite concurrent changes.
- Raw exports are kept local. XML parsing prohibits DTDs and external entity resolution. Structural comparisons are conservative candidates, not validated HIPS semantics. No volatile fields are silently ignored. Unexplained changes stop acceptance.
- Every stage distinguishes PASS, FAIL, OWNER_REPORTED and UNVERIFIED. Manual confirmation is not automated log verification. This kit cannot prove programmatic rule insertion, signing/import, or add-twice idempotency.

**Reject alternatives for now:** guessing HIPS XML risks changing unrelated settings; unobserved UI Automation controls risk clicking the wrong rule; reverse-engineering the protected log database is not a documented local interface; `runas /trustlevel` is not proof of a normal-user token; temporary scheduled tasks add unnecessary privileged state. None are used. We do not weaken HIPS, Self-Defense, authorization or any ESET service.

ESET documents password-authorized import using official `XmlSignTool` and its interactive password prompt. Future import work must keep passwords inside that official prompt, not command arguments, settings or transcripts. No password is requested by this kit.

## Files, privacy and rollback

Evidence uses unique run directories below `%USERPROFILE%\LOLRMM-Evidence`; the copied test executable uses `%LOCALAPPDATA%\LOLRMM-POC`. Local ACLs are restricted to the invoking user and Administrators. Network/synced/reparse locations are rejected; keep the host free of other configuration writers during the test.

The runner records `baseline.xml`, `with-manual-rule.xml`, `after-removal.xml`, a private `result.json`, run status and shareable `RESULTS.txt`. The sanitization report intentionally withholds raw rule XML until its schema and field allowlist are reviewed. A generic XML diff can expose unrelated secrets even when usernames are removed. Do not upload raw exports, worker diagnostics or `result.json`.

If the run stops after you may have added the rule, manually open ESET HIPS Rules. Locate exactly `LOLRMM POC TEST - LolrmmEsetTest`, confirm its exact copied-executable target, and remove only it. Run the executable again and confirm `Test Application`. A warning means cleanup is unresolved, not silently successful. There is no guaranteed unattended rollback; process termination, window closure or power loss cannot be handled by `finally`. Keep these instructions available outside the runner.

## Reported target, not a support claim

Owner-reported target: Windows 11 Pro 25H2 build 26200.9457, Windows PowerShell 5.1, ESET Security 19.2.10.0, `C:\Program Files\ESET\ESET Security\ecmd.exe`, FileVersion 10.67.16.0. The Ultimate 19 help is a research reference, not proof that ESET Security uses the same UI/XML. Stop if it differs.

All consumer ESET versions are a desired future compatibility scope. Unknown versions remain unvalidated. Business/Endpoint/PROTECT products are excluded. No background services, drivers, scheduled tasks, exclusions, allow rules or firewall rules are created.

## Root cause of the prior attempt

**NOT DETERMINED:** the previous script and exact error were not supplied. This is a clean recreation, not a verified fix to an identified prior defect. The design avoids known classes of launcher failure: whole-controller elevation, unsigned scripts under AllSigned, lost child exit codes, lexicographic version selection and hidden UAC failures. These are preventive design choices, not claims about what caused the old failure.

The process-local `-ExecutionPolicy Bypass` permits reviewed unsigned scripts to run; it changes no persistent execution-policy setting and cannot override organizational policy. Verify the ZIP's outer checksum and source before running. Internal hashes establish package consistency only, not publisher authentication. No public licensed release is created; this is the owner's test bundle.

## Test plan and verification

Dependency-free helper tests:

```powershell
powershell.exe -NoProfile -File poc\automated\tests\Test-Kit.ps1
```

Linux helper verification:

```text
pwsh -NoProfile -File poc/automated/tests/Test-Kit.ps1
```

Hosted Windows 2022/2025 CI runs the tests on Windows PowerShell 5.1, parses every shipped script, verifies ASCII/CRLF constraints, builds a self-contained x64 test EXE, smoke-tests its output and packages an explicit allowlist. `PROVENANCE.txt` records the source SHA. Successful CI proves those checks, NOT live ESET ACL/export/UI/log/enforcement behavior. See the delivered verification note for actual results.

Live owner acceptance still required: UAC, same-account worker identity, private ACLs, actual export success, manual exact-rule block plus matching log, cleanup, byte/structural preservation and any compatibility differences. Fully automated Phase 1 remains blocked until real rule/log evidence allows a validated adapter.

## Official references

- https://help.eset.com/esu/19/en-US/idh_config_ecmd.html - elevated export; destination folder must exist; export works with ESET CMD off; signed/password-authorized import.
- https://help.eset.com/esu/19/en-US/idh_importexport_config.html - supported configuration import/export.
- https://help.eset.com/esu/19/en-US/idh_hips_editor_single_rule.html - manual HIPS rule fields; exact mapping remains empirical.
- https://help.eset.com/esu/19/en-US/idh_page_logs.html - HIPS log UI.

LOLRMM and ESET do not endorse this project. This adds no antivirus signatures.
