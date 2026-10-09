# ESET HIPS XML and POC results — pending Phase 1

**Status: public native XML sample discovery and local fixture probes completed; owner-live POC remains unverified.** ESET KB7375 supplies an official small consumer HIPS ITEM/NODE append example; a retrieved community export identifies itself as consumer 15.0.18 and contains candidate block/start-operation fields. Neither is a current-build owner export or proof of import/enforcement. The narrowed candidate is specified in ADR 0002; do not certify ESET 19 merely because its export resembles these samples.

This document is the evidence record required by the Phase 1 gate. Use sanitized configuration samples captured from the exact ESET consumer product/version under test. Never commit passwords, license data, personal paths, machine identifiers, or other sensitive settings. Keep an untouched local backup outside source control where required.

## Environment record

- Product / edition:
- ESET version/build:
- Windows version/build:
- HIPS status:
- ESET CMD status and setup source:
- `ecmd.exe` path/version:
- `XmlSignTool` path/version:
- Test environment ownership/approval:
- Date:

## Evidence required

1. Clean baseline export and cryptographic fingerprint.
2. Export after manually creating a harmless `LOLRMM POC TEST` HIPS block for `LolrmmEsetTest.exe`.
3. Sanitized diff identifying exact rule fields, IDs/order, action, operation, target/path, logging, notification, and unrelated configuration.
4. Programmatic insertion from a clean export; XML validation and proof unrelated sections/rules were preserved.
5. Official signing command/authorization behavior if required; no secret in logs or command arguments.
6. Import exit/result, fresh re-export, parsed verification.
7. Execution test: program blocked by ESET, HIPS event logged, notification behavior recorded.
8. Remove only the generated managed rule; verify program starts again.
9. Verify unrelated manually created user rule/settings survive and a second unchanged apply is idempotent.
10. Exact failures, caveats, and owner acceptance decision.

## Results

No results recorded. Phase 1 must stop if any required POC condition fails; full application work is not authorized until the gate is explicitly accepted.
