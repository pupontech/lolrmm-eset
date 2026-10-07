# ESET HIPS proof of concept

Phase 1 is the architecture gate. The owner-selected route is an isolated, owner-run ESET Security Ultimate 19.2.x Windows test machine or VM. Agents do not provision VMs or mutate ESET.

Start with [the owner-run preparation and evidence guide](OWNER-RUN.md). Download `LolrmmEsetTest-win-x64.zip` only from a successful GitHub Actions POC test-app workflow run. The CI build/smoke test does not prove ESET behavior.

The POC must ultimately prove the full flow on the selected environment:

`baseline export → manual harmless HIPS block rule/export → programmatic insertion into preserved config → validation/signing if required → ecmd import → fresh export/verification → executable blocked and logged → remove only the managed rule → executable runs again`

The manual rule’s source/target mapping is a hypothesis to verify, not a product claim. Preserve unrelated HIPS rules and configuration. Keep full XML exports and unsanitized evidence local; share only a sanitized HIPS rule diff if needed. If any required step fails or behavior is unclear, stop and document it; do not widen the rule or continue to Phase 2. These instructions do not add XML-generation code; that implementation and verification remain part of Phase 1.
