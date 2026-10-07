# Phase 0 research — LOLRMM → ESET

**Research date:** 2026-10-07
**Status:** Phase 0 source review complete; no ESET installation, configuration, XML fixture, or enforcement test was performed.
**Evidence labels:** `DOC` = official documentation; `OBS` = direct read-only fetch/measurement; `UNKNOWN` = not established and must not be assumed.

## Executive finding

- Official ESET 19.x documentation shows that HIPS rules support Block/Allow/Ask and a `Start new application` operation, with logging and notification controls.[3][4]
- ESET Security Ultimate 19.x documents local XML configuration import/export through ESET CMD and official signing when Advanced Setup password authorization is used.[8]
- The latest-version page retrieved for this research lists ESET Security Ultimate 19.2.10.0, released August 27, 2026, as Full Support.[1]
- ESET Security Ultimate is part of the ESET HOME Security Ultimate subscription tier.[2]

**The architecture is still unproven.** I found no reviewed public documentation specifying the exported custom-HIPS-rule XML schema or demonstrating programmatic rule insertion and import.[unverified] The reviewed documentation also does not establish actual execution blocking for the proposed source/target combination.[unverified] The mandatory Phase 1 POC remains a hard gate; do not begin the full application until that real ESET round trip and harmless-executable block test passes.

## Current product and supported-version baseline

| Finding | Evidence | Applicability / boundary |
|---|---|---|
| Project primary target: ESET Security Ultimate 19.2.10.0, released 2026-08-27 and listed as Full Support. The same page also lists ESET NOD32 Antivirus, ESET Internet Security, and ESET Smart Security Premium at 19.2.10.0 Full Support; ESET 18.2.18.0 is Limited Support.[1] | `DOC`, ESET latest versions page | Use ESET Security Ultimate 19.2.x as the initial research/POC target. Other products are not validated by this project; the live schema still needs to be captured from the exact installed build. |
| ESET Security Ultimate is the Windows application; ESET HOME Security Ultimate is the subscription tier containing it.[2] | `DOC`, ESET KB8508 | Describe the locally installed product as ESET Security Ultimate. Do not imply that ESET HOME cloud/account management is the configuration API, and do not conflate it with ESET PROTECT. |
| HIPS is enabled by default in ESET Security Ultimate 19, but ESET exposes an enable/disable setting.[3] | `DOC`, version 19.x user guide | Detect HIPS readiness; do not silently change the user's ESET settings. Default-on documentation is not proof that it is enabled on a given PC. |
| ESET product documentation links to version 18.x, but this project has not tested 18.x or other consumer products.[1][3] | `DOC` plus no local test | No compatibility claim for other products/versions until their local ESET CMD/HIPS behavior and XML adapter are separately validated. Unknown major versions remain read-only. |

## ESET HIPS behavior established by documentation

- ESET 19 HIPS rules expose a name, enabled state, action (Allow/Block/Ask), operation(s), sources, targets, logging severity, and Notify option. The documented `Start new application` operation covers starting new applications/processes.[4] This confirms that the UI has relevant native rule concepts, but does **not** prove the intended programmatic rule shape or that every LOLRMM indicator is safe to represent.[4]
- HIPS rule sources are the application(s) that trigger an event; targets are the file, application, or registry entry related to the operation.[4][5]
- Therefore the compiler must distinguish whether a product executable is a source or target; the correct launch-blocking configuration for `LolrmmEsetTest.exe` must be discovered in the POC.[4][5]
- The HIPS rule editor documents logging severity and a user notification popup. The HIPS log records the triggering application, whether the rule permitted/prohibited the operation, and the rule name.[4][7] Actual log and notification behavior still requires the POC.[unverified]
- In ESET 19, all user-created HIPS rules have the same priority; more-specific rules outrank less-specific rules, and internal higher-priority rules are not exposed to the user.[5] There are no user-facing top/bottom ordering controls.[5] Do not invent an XML order/priority field or promise to override ESET's internal rules.
- The HIPS path picker selects a file/application path; selecting a folder includes applications located there.[6] A folder target is consequently broader than one executable and must be constrained by a narrow, justified directory.[6]
- ESET documents restricted wildcard support: `*` is the wildcard for file targets, and its documented semantics extend from the specified path onward.[4] Do not assume shell globbing, regex, environment-variable expansion, or that arbitrary LOLRMM path strings are accepted.[unverified] Support for `%ProgramData%`, `%APPDATA%`, user profiles, Temp, relative names, or bare filenames remains `UNKNOWN` until tested.[unverified] Reject broad patterns and generic roots.
- The reviewed ESET HIPS documentation does not establish matching by SHA hashes, signer identity, certificate thumbprint, Sigma logic, or arbitrary PE metadata.[unverified] Keep those LOLRMM fields informational in v1; this is a documentation gap, not a claim that no ESET feature anywhere can use them.

## ESET CMD, authorization, signing, and configuration files

### Documented local command workflow

ESET Security Ultimate 19 documents ESET CMD as its advanced local command-line configuration mechanism. The documented examples are `ecmd /getcfg <path>` to export and `ecmd /setcfg <path>` to import. Advanced commands require administrator privileges and are local-only; the product guide says export continues to work when ESET CMD is disabled, while import requires ESET CMD to be enabled.[8] ESET's support article says `ecmd.exe` is typically in the product installation directory and is not automatically placed on PATH.[9]

One-time enablement is a manual ESET Advanced Setup action (User interface → ESET CMD → enable advanced ecmd commands). The official support article warns against running without an authorization method because unsigned configurations could then be imported.[8][9]

### Password authorization and XmlSignTool

ESET documents two authorization modes: none, which it does not recommend, and Advanced setup password. With password authorization, the XML must be signed and the target installation's Advanced setup password is required for import.[8] The official ESET 19 guide directs users to ESET's `XmlSignTool` and documents `/version 2` for the current ESET Security Ultimate version; `/version 1` applies to versions earlier than 11.1. It prompts the operator to type and re-type the Advanced setup password.[8] The official tools page describes XmlSignTool as the ESET utility for signing XML configuration files.[12]

Do not implement the signing algorithm, pass the password in process arguments, or store it. A GUI-to-console secure interactive flow, cancellation/error behavior, and the exact currently distributed XmlSignTool binary version still need validation in the POC.[unverified] Product documentation supports invoking the official tool; it does not establish a safe programmatic password-injection interface.[unverified]

### Import/export scope and preservation

ESET 19 documents importing/exporting the customized product `.xml` configuration as a configuration backup/transfer mechanism.[10]

ESET's consumer-product support instructions describe importing an XML configuration to make the target product configured like the source.[11]

This supports the brief's conservative workflow: export the existing configuration, preserve a before-backup, modify only known app-owned HIPS rules in a copy, validate/sign/import through ESET, then export again and verify.[10][11]

**UNKNOWN:** exact XML root/sections, rule attributes and IDs, rule ordering representation, import merge/replace behavior for a minimal change, preservation of unknown XML, error codes, concurrent-change detection, and whether all consumer products accept identical rule XML.[unverified] The program must not generate a full configuration from scratch or mutate ESET until the captured-version POC verifies the round trip.

## LOLRMM source and live snapshot

The upstream project documents JSON and CSV APIs and describes the JSON result as an array of cataloged tools.[16][19] The canonical API is `https://lolrmm.io/api/rmm_tools.json`; website scraping is unnecessary.[13]

**OBS — read-only HTTPS fetch on 2026-10-07:** HTTP 200; JSON root was a list of 358 objects (97 `RAT`, 261 `RMM`), 2,259,194 bytes, SHA-256 `265b6f437f26da7a315ce4ed0ebb9b2d38afb7c3c0ac022faa04e8052e77bf83`.[13] A fresh homepage extraction on the same date displayed `CATALOG ENTRIES 358` and `358 of 358 tools`, matching the API snapshot.[21]

An earlier independent review observed a homepage count of 355; a fresh 2026-10-07 extraction returned 358. The source is mutable and the cause of the differing page observation is not established, so treat counts as dated snapshots, not stable identifiers.[21][unverified]

The exact API response is preserved locally at `research/evidence/lolrmm-rmm_tools-2026-10-07.json`; `research/evidence/capture_lolrmm_snapshot.py` records its counts and SHA-256 and refuses to overwrite an existing snapshot. The raw JSON is git-ignored pending confirmation of redistribution terms; it is not app runtime data.[13]

The observed feed is not a rigid single-shape schema: `Details.PEMetadata` was an object in 288 records, an array in 65, and null in 5.[13]

Optional top-level fields were absent from some records (`Author` and `Detections` in 3 each; `Acknowledgement` in 1); `CodeSigning` appeared in 156 records and `FileHashes` in 44.[13]

One record also exposed a top-level `InstallationPaths` field.[13]

AnyDesk and TeamViewer were both present; their feed entries include path and executable-name indicators.[13]

The parser must tolerate missing/null/wrong-shaped fields and multiple metadata records; names and schema locations must not be assumed fixed.[13]

The optional `rmm_domains.csv` feed returned HTTP 200 with header `URI,RMM_Tool` and 748 data rows; `rmm_certificates.json` returned HTTP 200 with a JSON-array root and 73 entries.[14][15] They are informational only for v1: network-domain enforcement and certificate blocking remain out of scope. The LOLRMM detections page publishes catalog-generated process/DNS Sigma references and tells users to tune them for approved RMM tools.[17] Do not translate Sigma/network logic into HIPS rules.

The upstream GitHub repository identifies Apache License 2.0.[18] Preserve attribution and link the source; verify the license's applicability to redistributed catalog data before bundling any copy.[18] Do not imply LOLRMM endorsement.[16]

## Technology recommendation

Microsoft's official support policy, updated 2026-09-08, lists .NET 10.0.12 as an active LTS patch through 2028-11-14.[20] **Recommendation:** start implementation on .NET 10 LTS and WPF for the smallest conventional native Windows desktop stack, x64. Pin/update to the latest supported servicing patch in CI. This is a stack recommendation, not evidence about ESET compatibility. No solution or application code has been created.

## Decisions, uncertainties, and phase gates

1. **Phase 1 remains mandatory.** Capture a baseline ESET 19.2 export and a manually created harmless HIPS test rule; diff them to discover the exact rule XML; remove it; generate an equivalent rule from the clean export in C#; officially sign only if required; import with ESET CMD; export and verify; prove the harmless executable is blocked and logged/notified; remove only the generated rule and prove execution works again; confirm unrelated settings/rules survive and repeat apply is idempotent. Stop if any step fails. No full application work before this passes.
2. **Test environment route is selected; evidence is pending.** On 2026-10-07 the owner chose to run the POC on their isolated Windows/ESET test machine or VM. The agent prepares the POC package and instructions but does not provision a VM or install/mutate live ESET. The owner-run route and evidence-handling rules are recorded in ADR 0001. GitHub Windows CI alone cannot prove native ESET enforcement.
3. **Current documentation does not prove the XML schema or actual blocking behavior.** Phase 1 must supply empirical evidence. Path matching beyond what the docs state, environment variables, HIPS log retention/viewing, notifications, signer/hash matching, unknown-version import, and XmlSignTool GUI interaction remain open until tested.
4. **Initial compatibility claim should be narrow:** document ESET Security Ultimate 19.2.x as the research target, but do not mark it “supported” until the POC and later owner-run integration tests pass. Other versions/products remain unsupported/read-only until validated.
5. **License for this project remains an owner decision.** The upstream LOLRMM license does not decide this application's license; do not create a project `LICENSE` file or publish a release without approval.

## Source index

All sources listed below were accessed on 2026-10-07. The generated source list retains each title and direct URL; the citation ledger stores the per-source access date. ESET behavior claims refer to the exact ESET 19.x consumer-product help pages unless otherwise stated.

## Sources

[1] https://help.eset.com/latestVersions/?lang=en — ESET latest supported versions
[2] https://support.eset.com/en/kb8508-eset-security-ultimate — ESET Security Ultimate product and subscription tier
[3] https://help.eset.com/esu/19/en-US/idh_hips_main.html — ESET Security Ultimate 19 HIPS overview
[4] https://help.eset.com/esu/19/en-US/idh_hips_editor_single_rule.html — ESET Security Ultimate 19 HIPS rule settings
[5] https://help.eset.com/esu/19/en-US/idh_hips_editor_main.html — ESET Security Ultimate 19 HIPS rule management and priority
[6] https://help.eset.com/esu/19/en-US/idh_hips_editor_add_path.html — ESET Security Ultimate 19 HIPS target path picker
[7] https://help.eset.com/esu/19/en-US/idh_page_logs.html — ESET Security Ultimate 19 log files
[8] https://help.eset.com/esu/19/en-US/idh_config_ecmd.html — ESET Security Ultimate 19 ESET CMD
[9] https://support.eset.com/en/kb7277-use-eset-command-line-ecmdexe-to-importexport-security-product-configurations-in-eset-endpoint-products — ESET CMD setup and import/export KB7277
[10] https://help.eset.com/esu/19/en-US/idh_importexport_config.html — ESET Security Ultimate 19 GUI XML import/export
[11] https://support.eset.com/en/kb3133-import-or-export-eset-configuration-settings-in-windows-home-products-using-an-xml-file — ESET home and small office XML import/export KB3133
[12] https://www.eset.com/us/download/tools-and-utilities — ESET official XmlSignTool download
[13] https://lolrmm.io/api/rmm_tools.json — LOLRMM JSON catalog API
[14] https://lolrmm.io/api/rmm_domains.csv — LOLRMM domains CSV API
[15] https://lolrmm.io/api/rmm_certificates.json — LOLRMM certificate JSON API
[16] https://github.com/magicsword-io/LOLRMM — LOLRMM upstream repository and API documentation
[17] https://lolrmm.io/detections — LOLRMM detections and Sigma references
[18] https://github.com/magicsword-io/LOLRMM/blob/main/LICENSE — LOLRMM Apache-2.0 license
[19] https://github.com/magicsword-io/LOLRMM/blob/main/README.md — LOLRMM upstream README/API usage
[20] https://dotnet.microsoft.com/en-us/platform/support/policy — .NET official support policy
[21] https://lolrmm.io — LOLRMM live catalog homepage
