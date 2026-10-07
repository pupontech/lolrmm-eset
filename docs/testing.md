# Testing and acceptance evidence

**Status: no implementation or live ESET tests yet.** Do not mark planned tests as passed. This file will separate automated tests, GitHub-hosted Windows tests, and owner-run live ESET acceptance.

## Evidence classes

| Class | Environment | Result / run / artifact | Date | Notes |
|---|---|---|---|---|
| Unit / static tests | Pending | Pending | — | — |
| GitHub Actions Windows runner | Pending | Pending | — | — |
| Owner-controlled ESET integration | Pending | Pending | — | Exact ESET/Windows version required |

## Required live integration scenarios

- [ ] Detection of supported consumer ESET, HIPS, ESET CMD, and `ecmd.exe`.
- [ ] Clean export, backup, programmatic owned-rule change, official signing if required, import, re-export, verification.
- [ ] Harmless selected test application is genuinely blocked by ESET and recorded in HIPS log; notification behavior noted.
- [ ] Removing the app-owned rule restores normal execution.
- [ ] Unrelated user HIPS rule and unrelated ESET configuration survive.
- [ ] Repeated Apply with no changes creates no duplicate rules.
- [ ] AnyDesk and TeamViewer default unselected; manual selection blocks; unselection removes only this app's rule.
- [ ] Backup rotation and restore.
- [ ] Failure cases: LOLRMM offline/bad response, ESET CMD disabled/missing, signing/import/export failures, unknown ESET version, access/disk failures, concurrent config change, verification mismatch.
- [ ] App closes after apply; ESET continues enforcement without a persistent app process.

## Release gate

A UI, generated XML, or successful import command alone is not completion. The Definition of Done in `docs/PROJECT_BRIEF.md` requires actual ESET enforcement evidence and owner acceptance. Keep red/unknown/skipped results explicit; never fabricate evidence.
