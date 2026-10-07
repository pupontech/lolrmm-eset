# Project brief — LOLRMM → ESET

**Status:** planning/setup only. This document captures the owner's requirements; it is not evidence that research or implementation has started.

## 1. Goal and user workflow

Build a deliberately small, open-source Windows desktop utility that downloads the public LOLRMM catalog, presents a searchable checklist, lets the user choose which remote-management products should be blocked, and directly synchronizes that choice into native rules in locally installed consumer ESET software. The intended flow is:

`Open → review list → choose → preview → Apply to ESET → done`

The application exits afterward. ESET performs ongoing enforcement. The app must not add a persistent process or implement its own process blocker.

## 2. Scope and terminology

- Primary intended target: ESET Security Ultimate / ESET HOME Security Ultimate for Windows. Support other currently supported consumer Windows ESET products only if they expose the verified required local HIPS and ESET CMD functionality.
- This is local integration. ESET HOME and ESET PROTECT are different products. No ESET PROTECT, Inspect, EDR, Endpoint Security, business licensing, MSP management, Connect, enterprise API, cloud-management, or multi-device features.
- Use native ESET HIPS (Host-based Intrusion Prevention System) for execution blocking. This project does **not** add custom antivirus/malware signatures. Describe outcomes as native ESET HIPS blocking rules, potentially logged/notified by ESET.
- Checked means “maintain LOLRMM-generated ESET blocking rules for this product.” Unchecked means “maintain no LOLRMM-generated rules for this product.” Unchecked is not an AV exclusion, HIPS allow rule, malware exclusion, or firewall allow rule.
- Do not block domains in v1. Do not uninstall/delete RMM software, clean registries, or add unrelated security products, dashboards, accounts, telemetry, AI, servers, services, drivers, scheduled jobs, or auto-sync.

## 3. Upstream LOLRMM data

Use structured public feeds, not website scraping. Canonical catalog: <https://lolrmm.io/api/rmm_tools.json>. Investigate as useful: <https://lolrmm.io/api/rmm_domains.csv>, <https://lolrmm.io/api/rmm_certificates.json>, and current Sigma/detection references. Record licensing/attribution and direct source links; never imply LOLRMM endorses this project.

Normalize useful fields when present: product/name/normalized name/category/description; executable and original filenames; paths; PE metadata; publisher/company/product; registry/filesystem artifacts; domains/ports; signer/certificate/hash metadata; references/Sigma; last modified. Treat the schema as evolving. Missing/null values, empty fields, strings instead of arrays, arrays instead of objects, malformed individual records, multiple executable records, duplicate indicators, and new fields must not crash the catalog. Keep unsupported metadata informational.

Recommended pipeline: `LolrmmClient → LolrmmParser → LolrmmNormalizer → RmmTool model`. Keep upstream DTOs separate from internal models and ESET XML. Cache the last valid catalog; load it immediately on startup, refresh over HTTPS with certificate validation/timeouts/retries, and replace the cache only after validation. On refresh failure, use valid cached data with a clear status. Refresh never changes ESET until the user explicitly applies.

## 4. Domain model, defaults, and selection persistence

Maintain normalized `RmmTool` records with stable ID/name/category/description, executable/original-file names, paths, informational indicators/references, last-modified value, content fingerprint, selection state, and compatibility state. Compatibility states: `READY`, `PARTIAL`, `NO_SAFE_HIPS_RULE`, `REVIEW_REQUIRED` (UI: Protected, Partial, Needs Review).

A centralized built-in default-allowed list matches AnyDesk and TeamViewer robustly and case-insensitively. On first launch, every safely representable RMM is selected/blocked except AnyDesk and TeamViewer, which remain visible and unselected. Newly discovered products appear automatically and receive those defaults; existing explicit user decisions survive catalog refreshes. Keep defaults separate from overrides. “Select All” includes AnyDesk/TeamViewer; “Select None” clears all; “Restore Defaults” restores checked except those two, asks before overwriting explicit choices, and never applies changes by itself.

## 5. Safe enforcement model

Only use indicators that current official ESET documentation and testing establish as safe/reliable for consumer HIPS. Prefer, in order, exact executable paths, exact application targets, verified path patterns, then narrow installation-directory targets. Do not assume consumer HIPS can match hashes, signer names, thumbprints, Sigma logic, arbitrary PE metadata, or network behavior. Hashes/certificates remain informational in v1; do not automatically block a publisher/certificate. Avoid version-specific hashes as the primary method.

Research exact support for absolute paths, folders, wildcards, environment variables and common locations (Program Files, Program Files (x86), ProgramData, per-user AppData, Temp). Never assume wildcard syntax or create broad targets such as `*.exe`, `C:\*`, or `C:\Users\*`. Maintain a safety denylist for generic Windows components including `explorer.exe`, `svchost.exe`, `services.exe`, `lsass.exe`, `winlogon.exe`, `csrss.exe`, `wininit.exe`, `smss.exe`, `cmd.exe`, `powershell.exe`, `pwsh.exe`, `rundll32.exe`, `msiexec.exe`, `wscript.exe`, and `cscript.exe`. If a detection depends primarily on such a component or an indicator could cause excessive blocking, mark `REVIEW_REQUIRED` and do not auto-generate a rule. Fail closed; never widen a rule to improve coverage.

Different tools can share indicators. Deduplicate enforcement when safe while retaining product attribution; do not create conflicting/redundant rules blindly.

## 6. ESET integration and ownership

Use only supported local mechanisms. Research current official documentation for current ESET consumer product naming/version, HIPS, ESET CMD, `ecmd.exe` equivalents for `/getcfg <path>` and `/setcfg <path>`, configuration import/export, authorization/password behavior, `XmlSignTool` version/syntax/signature behavior, HIPS rule matching, logging, and notification settings. Do not rely on old tutorials or infer compatibility from ESET 17/18.

Use an abstraction such as `IEsetConfigurationAdapter` with a version-specific adapter only after that version's format is validated (for example, an ESET 19 adapter). Unknown major versions are read-only: show a compatibility warning and diagnostic output, never modify blindly. Detect installed consumer product/version, HIPS, `ecmd.exe`, and whether ESET CMD is ready; offer concise manual setup instructions if needed. Prefer UAC elevation only for the privileged operation; do not create a SYSTEM service.

Every app-owned rule must have a deterministic name prefixed exactly `LOLRMM Block - `, e.g. `LOLRMM Block - ScreenConnect`; multiple rules use stable numbered suffixes. Modify/remove only rules proven to match this exact ownership scheme. Preserve administrator-created rules and unrelated ESET configuration.

No direct protected-registry changes, internal database/file edits, executable patching, process injection, Self-Defense disablement, service tampering, undocumented IPC, or GUI click automation as primary integration. Launch `ecmd.exe`/official signer directly (no `cmd.exe /c` unless unavoidable), separate/escape arguments, capture exit code/stdout/stderr, and never expose secrets in arguments or logs. XML parsing must disable DTD/external entity resolution; catalog text must not inject XML. Use secure per-user/per-process temporary directories, controlled backups, validation, cleanup, and fail-closed writes.

## 7. Apply/preview transaction and rollback

Preview and Apply must share the same diff engine. Model desired vs current application-owned rules as `ADD`, `UPDATE`, `REMOVE`, `UNCHANGED`; Apply twice with unchanged inputs must yield zero changes and no duplicates.

Apply sequence:

1. Detect compatible ESET and readiness; reject unknown versions or unavailable prerequisites safely.
2. Export current configuration once; fingerprint it and preserve an untouched before-backup before modification.
3. Parse safely; identify only app-owned HIPS rules; calculate desired rules and diff.
4. If practical, detect concurrent external configuration changes before import and abort/recalculate if changed.
5. Remove stale app-owned rules, add/update desired owned rules, preserve all other XML/configuration.
6. Validate XML/root/expected HIPS structure, unrelated sections, rule shape, IDs/names, unsafe broad rules, and duplicates. On validation failure, do not import.
7. Sign only with official `XmlSignTool` when current ESET authorization requires it. Never recreate signing algorithms or bypass authorization. Prefer secure interactive signing; otherwise use a suitable Windows-native secure secret store only if necessary. Never persist plaintext ESET password in settings, DB, logs, crash reports, or command line.
8. Import using official ESET CMD; report import failures plainly.
9. Export again and verify expected actual owned rules and relevant unrelated configuration. Report success only on verified match. If imported but verification differs, report that exact state, not success.

Keep a configurable small backup rotation, default five, separately from temporary files. Include “Restore Previous Configuration” only under advanced/settings. Restores must use the same safe validation/sign/import/verification process. Record diagnostics locally without telemetry. Logs may include startup, detection/version, command/catalog counts, warnings, diff, export/backup/sign/import/verification results and errors; never secrets.

## 8. Minimal GUI and persistence

Native Windows GUI; simplest stable maintainable choice between WPF and WinUI 3, with WPF preferred unless current research warrants otherwise. Strong preference for C# and current stable .NET appropriate to the release date. No Electron, browser/web wrapper, Docker, web server, or microservices.

Main view needs only ESET readiness, LOLRMM updated status, search by tool/vendor/executable/category, checklist, selection controls, selected-to-block count, Preview Changes, Apply to ESET, simple Protected/Partial/Needs Review counts, last-apply status, Refresh LOLRMM, and settings/diagnostics. Product details may be secondary. Optional filters: All/Blocked/Allowed/Needs Review. No charts, scores, account systems, or telemetry dashboards. The UI must communicate “pending”, “protected”, “partial”, “needs review”, “not selected”, and “apply failed” accurately.

Use simple JSON or SQLite for local selections/cache/settings/mappings/last sync. Do not store ESET secrets. Keep GUI handlers out of XML/rule implementation; use the service pipeline.

## 9. Mandatory phase order

See `docs/roadmap.md`. The user explicitly requires this sequence:

0. Research current official sources and record `docs/research.md`.
1. Prove ESET HIPS XML round-trip and actual block in `poc/`; this is the hard gate before full development.
2. Reusable ESET detection/export/configuration/rule management/sign/import/verify/backup library.
3. LOLRMM download/cache/parse/normalize/validate.
4. Safe rule compiler and safety checks.
5. Desired/current diff, preview, apply plan.
6. Minimal GUI.
7. Real ESET Windows integration and failure testing; `docs/testing.md` evidence.
8. Packaging, complete docs, GitHub-ready release.

### Phase 0 research deliverable

Verify current official ESET consumer docs/product naming, HIPS, ESET CMD command syntax and enablement, XmlSignTool syntax/authorization, import/export, matching/path/wildcard behavior, HIPS logging/notification, supported product versions/elevation. Verify LOLRMM API shape and current attribution/license/detection references. Cite URLs, access dates, exact version/doc names, tested facts vs assumptions, and unresolved questions. Do not start the full app.

### Phase 1 POC gate

No LOLRMM or GUI. In an owner-approved isolated Windows/ESET environment, capture a clean baseline export; manually add a harmless HIPS block rule for `LolrmmEsetTest.exe`; export the manual-rule config; diff them to discover the exact version-specific XML. Remove the manual rule, export clean config, programmatically insert an equivalent rule with C#, preserve unrelated config, validate and officially sign if required, import via `ecmd`, export and verify. Run the harmless test executable and prove ESET blocks it, logs the event, and notifies as configured; remove the generated rule and prove the executable runs again. Verify unrelated user rule/settings survive and repeat apply is idempotent. Store sanitized fixtures/evidence and document exact commands, ESET version, results, and failure points. If any required step fails, stop and re-evaluate architecture; do not proceed to Phase 2.

The source brief asks for a Windows VM and real ESET tests. The owner's standing policy says agents must not provision VMs/install live software and instead use GitHub Actions Windows runners plus owner live testing. This is a blocking owner decision before any Phase 1 mutation; see ADR 0001.

## 10. Required tests

- LOLRMM: valid catalog, missing/null/malformed individual entries, empty/wrong-shaped fields, duplicates, multiple PE records, path arrays, name normalization, AnyDesk/TeamViewer defaults, newly discovered defaults, explicit-choice persistence, cache fallback/offline/malformed response.
- Safety/compiler: exact file/path, verified vs unsupported wildcard, dangerous broad paths, generic Windows binary, duplicates/shared indicators, multiple paths, no usable path, changed normalized fingerprint, compatibility state.
- ESET XML: sanitized real-version fixtures; parse/round-trip; preserve unknown sections and unrelated custom HIPS rules; add/update/remove/multiple rules; duplicate prevention; malformed XML/missing HIPS; secure XML parser; version adapter; safe validation.
- Diff: equality/no-op; add/update/remove; upstream deletion; unchecked removes only owned rules; unrelated rule untouched; repeated Apply idempotent.
- Integration and failure cases: product/HIPS/ecmd detection, export, signing, import, re-export verification, actual block/log/notification, removing managed rule, unrelated config preservation, AnyDesk/TeamViewer default/manual check/uncheck, backup/restore, offline LOLRMM, ecmd disabled/missing, wrong password/signing/import/export/disk/access failures, unknown major version, concurrent configuration change, verification mismatch.

Use sanitized fixtures from a real validated supported ESET export. Do not fabricate integration results.

## 11. Release/documentation requirements

Deliver a normal x64 Windows build that needs no development tools installed; prefer a simple self-contained executable/installer. Prepare for future Authenticode signing, distinct from ESET config signing. Use semantic versioning. README must explain scope, requirements, supported products (only verified), HIPS model, local configuration workflow, LOLRMM source, defaults, setup/apply/restore, backups, troubleshooting, security, limitations, build/test/release, attribution, and trademark disclaimer. State clearly: this does not add AV signatures; ESET enforces native HIPS rules; the app need not stay running. Warn that listed RMM tools can be legitimate and blocking can disrupt authorized support; AnyDesk/TeamViewer are intentionally unselected by default. Do not imply LOLRMM/ESET endorsement. License is not selected yet; choose before distributing.

## 12. Definition of done

Do not claim completion merely because the UI/catalog/XML/import command exists. Completion requires the supported ESET installation to demonstrate: catalog loads; AnyDesk/TeamViewer defaults; other safe tools default selected; selections persist/change; direct ESET apply; native HIPS rules block a selected harmless/authorized test RMM executable; ESET logs the block; unchecking removes only this app's rule; unrelated user rules/settings survive; repeat apply creates no duplicates; backup/restore works; and the application can close while ESET continues enforcement. Evidence must distinguish automated tests, hosted Windows CI, and owner live-ESET acceptance.
