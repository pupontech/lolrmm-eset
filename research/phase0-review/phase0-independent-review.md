# Phase 0 independent source and citation review

Review date: 2026-10-07
Scope: read-only audit of `docs/research.md` against the project brief, ADR 0001, current official ESET consumer documentation, and the live LOLRMM pages/API references. No ESET installation, XML mutation, or POC was performed.

## Verdict

Conditional pass on the ESET documentation summary: the checked product/version, HIPS rule concepts, ESET CMD commands, signing instructions, and logging statements are supported by current official ESET sources, and the research appropriately says XML structure and actual blocking remain unproven. Do not treat the research as establishing compatibility or HIPS blocking.

Before owner acceptance, correct the two definite record-quality issues below: the Phase 0 research misstates the owner test-route decision as unresolved, and its source-index note claims access dates are rendered when the source list does not show them. Also reconcile/label the LOLRMM count and preserve reproducible evidence for the reported snapshot measurements.

## Confirmed errors and gaps

### 1. Test-route status in `docs/research.md` conflicts with the accepted ADR

`docs/research.md` lines 84–89, especially item 2 at line 87, says the test-environment conflict is unresolved and that the owner must still provide/approve a route or revise policy. ADR 0001 lines 3 and 8 says the owner-run ESET POC route was selected on 2026-10-07: the owner will run it on their isolated Windows/ESET machine or VM, and the agent prepares the POC package and steps. ADR 0001 lines 17 and 23 retain the proper restriction that owner-run ESET evidence is pending and blocks Phase 2.

Suggested correction: say the route is selected (owner-run), while the actual environment readiness and Phase 1 evidence remain pending. Keep the no-agent-VM/live-ESET-mutation gate. This is a documentation-state error, not authorization to perform Phase 1.

### 2. Source-index access-date assertion is false as rendered

`docs/research.md` line 94 says: “Direct URL/access date and source title are retained in the rendered source list.” The rendered list at lines 98–117 has URLs and titles but no access dates. The external citation ledger records `accessed: 2026-10-07` for its entries (for example ledger IDs 1 and 3), but that task-local path is not part of the rendered source list or the repository deliverable.

Suggested correction: include access dates in the source list (or generated document), or remove the claim that they are rendered there. This matters because the brief at `docs/PROJECT_BRIEF.md` line 95 explicitly asks for URLs, access dates, exact version/doc names, and the distinction between tested facts and assumptions.

### 3. LOLRMM count/snapshot needs reconciliation and reproducible evidence

`docs/research.md` lines 64–74 reports an API snapshot of 358 objects (97 `RAT`, 261 `RMM`), 2,259,194 bytes, a SHA-256, and field-shape distributions. The current public catalog page at <https://lolrmm.io/> renders “RMM Tools Total: 355” and links to the JSON and CSV APIs. That displayed total may use a different category/snapshot definition than the 358-object API observation, so this is not by itself proof that the JSON count is wrong; it is an unresolved discrepancy that should be labeled and reconciled before presenting the figures as current.

The cited API at <https://lolrmm.io/api/rmm_tools.json> is mutable. The task-local ledger entry 13 retains only one example record excerpt, not the complete response or a method/transcript supporting the reported aggregate counts, field-shape counts, byte size, and hash. Preserve a dated raw snapshot or equivalent reproducible measurement evidence (with the hash) and distinguish total API records from the website's displayed “RMM Tools Total.”

## Non-blocking wording clarification

`docs/research.md` line 20 calls ESET Security Ultimate 19.x the current full-support consumer product baseline. The ESET latest-versions page at <https://help.eset.com/latestVersions/?lang=en> confirms ESET Security Ultimate 19.2.10.0 (released August 27, 2026) as Full Support. The same page also lists ESET NOD32 Antivirus, Internet Security, and Smart Security Premium at 19.2.10.0 as Full Support. Since the project explicitly makes Security Ultimate its primary target, this is not a compatibility error; phrase it as the project's primary target rather than implying it is the only full-support consumer product.

## Source checks and confirmed boundaries

- ESET Security Ultimate is identified as the Windows application in the ESET subscription article; the same article says it is part of the ESET HOME Security Ultimate tier: <https://support.eset.com/en/kb8508-eset-security-ultimate>. The project correctly distinguishes the local product from the subscription tier.
- ESET Security Ultimate 19 HIPS documentation confirms Block/Allow/Ask, `Start new application`, source applications, targets, logging severity, and user notification: <https://help.eset.com/esu/19/en-US/idh_hips_editor_single_rule.html>. Rule management confirms same priority for user-created rules and greater priority for more-specific rules: <https://help.eset.com/esu/19/en-US/idh_hips_editor_main.html>. This supports the documented UI concepts, not an exported XML schema or actual launch-block result.
- The ESET 19 HIPS docs say that HIPS is enabled by default, but the live setting is configurable; they also warn that not all system operations are monitored: <https://help.eset.com/esu/19/en-US/idh_hips_main.html>. The research correctly avoids assuming an individual installation is enabled and retains a real block test as a gate.
- HIPS path selection includes applications in a selected folder, and the HIPS rule page documents restricted wildcard use: <https://help.eset.com/esu/19/en-US/idh_hips_editor_add_path.html> and <https://help.eset.com/esu/19/en-US/idh_hips_editor_single_rule.html>. The latter describes the “this path, or any path on any level after that symbol” behavior in a paragraph that first discusses registry paths and then notes wildcard use for file targets. The research appropriately limits its interpretation and does not claim environment-variable, hash, signer, or arbitrary PE-metadata matching.
- ESET Security Ultimate 19's ESET CMD page confirms `ecmd /getcfg <path>` and `ecmd /setcfg <path>`, administrator privileges, local-only operation, password authorization requiring a signed XML configuration, XmlSignTool usage, `/version 2` for the current product, and password prompting: <https://help.eset.com/esu/19/en-US/idh_config_ecmd.html>. ESET's log documentation confirms HIPS log entries can include the triggering application, permitted/prohibited result, and rule name: <https://help.eset.com/esu/19/en-US/idh_page_logs.html>. The research still correctly leaves schema, preservation, and actual enforcement to Phase 1.
- LOLRMM's current site describes its CSV/JSON APIs and its detections as material to tune for approved tools: <https://lolrmm.io/> and <https://lolrmm.io/detections>. Its current README describes the API as a JSON array: <https://github.com/magicsword-io/LOLRMM/blob/main/README.md>. Its repository license page identifies Apache License 2.0: <https://github.com/magicsword-io/LOLRMM/blob/main/LICENSE>. The research's caution that this does not decide the product's own license and does not establish redistribution rights for a bundled data snapshot is prudent.

## Scope and safety

No evidence here demonstrates HIPS XML compatibility, supported import semantics for programmatically edited rules, or actual blocking. Preserve the Phase 1 gate exactly; do not build the application or claim ESET compatibility from these docs alone. This review modified only this review report; it did not change `docs/research.md`, source files, or ESET configuration.