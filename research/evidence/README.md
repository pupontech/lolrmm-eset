# Phase 0 evidence capture

`capture_lolrmm_snapshot.py` fetches the public HTTPS JSON API, verifies that the response is a JSON array of objects, refuses to overwrite a dated snapshot, writes the raw response locally, and prints the count, category totals, byte length, and SHA-256.

Run from the repository root:

```text
python3 research/evidence/capture_lolrmm_snapshot.py
```

The resulting `lolrmm-rmm_tools-YYYY-MM-DD.json` is intentionally git-ignored. It is a local research artifact, not app runtime data and not part of the distributable. The report records the hash and measurement date. Do not upload full ESET configuration exports here.

Canonical API: <https://lolrmm.io/api/rmm_tools.json>

Upstream project/license: <https://github.com/magicsword-io/LOLRMM> · <https://github.com/magicsword-io/LOLRMM/blob/main/LICENSE>

The owner has not yet approved redistribution of a bundled catalog snapshot; the application is intended to fetch the current feed at runtime. Preserve upstream attribution and do not imply endorsement.
