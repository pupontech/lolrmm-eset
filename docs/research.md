# Research findings — pending Phase 0

**Status: not started.** This file is a Phase 0 deliverable placeholder only. No current ESET behavior or LOLRMM schema has been verified by this project yet. Do not treat the proposed commands or concepts in the brief as validated facts.

Phase 0 must use current official upstream sources and include the access date, document title/version, direct URL, exact finding, applicability to consumer ESET, and confidence/evidence class. Distinguish documented behavior, observed behavior, and open questions.

## Required ESET research

- Current ESET Security Ultimate / ESET HOME Security Ultimate for Windows naming, supported versions, and applicable consumer-product documentation.
- HIPS capabilities and exact custom application-rule semantics: action, operation, source/target, ordering/IDs, logging, notifications, path matching, wildcard/environment-variable behavior, and limitations.
- ESET CMD setup/enablement and current supported `ecmd.exe` export/import command syntax, authorization requirements, and elevation requirements.
- Current configuration export/import behavior, schema/version differences, required root/sections, and safe compatibility strategy.
- Current official `XmlSignTool` availability, syntax/version, signing requirements, password handling, and whether protected configurations require signing.
- Security implications, failure behavior, and any limitations for consumer products.

## Required LOLRMM research

- `https://lolrmm.io/api/rmm_tools.json` structure, update behavior, license/attribution, and stable identifiers.
- As useful: `https://lolrmm.io/api/rmm_domains.csv`, `https://lolrmm.io/api/rmm_certificates.json`, and current Sigma/detection references.
- Real sample shapes and schema variance, including null/missing/wrong-shaped values and duplicates.

## Findings template

| Topic | Source (title/version/date) | Direct URL | Verified finding | Product/version applicability | Open questions |
|---|---|---|---|---|---|

## Phase 0 exit checklist

- [ ] Sources are current, official where applicable, and linked directly.
- [ ] Every ESET claim is scoped to exact consumer product/version or labeled unknown.
- [ ] HIPS path/wildcard, logging, notification, ESET CMD, import/export, authorization, and signing are covered.
- [ ] LOLRMM feed shape, attribution, and normalization concerns are covered.
- [ ] Findings distinguish docs from empirical evidence; no unsupported claim is promoted to fact.
- [ ] Test-environment conflict is explicitly presented for owner decision before Phase 1.
- [ ] Review completed and Phase 1 prerequisites are clear. No implementation may start until the POC gate passes.
