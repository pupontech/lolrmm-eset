# Phase 1 owner-guide safety and citation review

Verdict: PASS (focused document review only; not Phase 1 acceptance)

Findings: None.

Scope and evidence reviewed

- Read `poc/OWNER-RUN.md` and `poc/README.md`, plus `docs/PROJECT_BRIEF.md`, `docs/roadmap.md`, `docs/research.md`, and `docs/decisions/0001-project-scope-and-gates.md`.
- Retrieved and checked the cited official ESET Security Ultimate 19.x pages for HIPS rule settings, ESET CMD, HIPS status, log files, and import/export settings ([1]–[5] in `poc/OWNER-RUN.md`). Also checked the research-cited official HIPS path-picker/rule-management pages and ESET support articles KB7277/KB3133.
- ESET documentation supports the described HIPS controls and `Start new application` operation, HIPS log fields, and `ecmd /getcfg` / `/setcfg` commands. It states advanced ecmd commands require administrator privileges, the export destination folder must exist, and export works even when ESET CMD is off. The guide correctly limits itself to the documented manual export and does not direct the owner to import XML or sign anything.
- `poc/OWNER-RUN.md:37` expressly marks the proposed source/target mapping as a POC hypothesis. No rule-specific statement asserts that the proposed combination has been proven to block. The rule is constrained to the exact `LolrmmEsetTest.exe` path (`:10`, `:34`); the guide disallows folders, wildcards, extra executables, and broader paths (`:5`, `:34`).
- The instructions require stopping on ambiguous choices/results and failures (`:5`, `:13`, `:45`, `:59`), keep full exports and raw evidence local (`:11`, `:21`, `:39`, `:50`, `:56`), and allow sharing only a minimal sanitized HIPS rule diff (`:57`). No password or secret is requested.
- The README (`poc/README.md:3–11`) and guide (`poc/OWNER-RUN.md:3`, `:52`) clearly say no agent ESET change/test has occurred and that manual observation does not prove XML preservation, programmatic insertion, import/re-export, or enforcement. This is consistent with ADR 0001 and the Phase 1 gate in the roadmap.

Checks performed

- `git diff --check -- poc/README.md` — exit 0.
- `git diff --check --no-index /dev/null poc/OWNER-RUN.md` — no whitespace diagnostics; exit 1 because the untracked guide differs from `/dev/null`.
- Direct source retrieval/check of the official ESET pages linked above; no ESET machine, configuration, or enforcement test was performed.

Limit: PASS means the guide and its citations meet this focused review. It is not evidence of ESET XML round-trip, programmatic import, blocking, logging, or unblocking success; those remain pending owner-run Phase 1 evidence.
