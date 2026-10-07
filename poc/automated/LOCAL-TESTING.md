# Local verification record

The initial Luna-written prototype was incomplete and failed the parent-run test entrypoint: it looked for the helper under `tests/Kit.Helpers.ps1`. It was not shipped. The parent repaired/rebuilt the runner and tests after a second Luna attempt remained incomplete.

Observed RED on the current test suite during reconstruction:
- Safe manifest parsing failed with a null-valued method call because a second regex overwrote `$Matches` before the first hash capture was stored. The hash is now captured before validating the filename.
- The complete-subtree insertion test failed because removing a child changed empty-element lexical serialization. The comparator now uses length-delimited, node-type/namespace/attribute/child structural fingerprints. A candidate remains UNVERIFIED, never an ESET semantic claim.

Observed GREEN:
`pwsh -NoProfile -File poc/automated/tests/Test-Kit.ps1` exited 0 with 32 checks passed on Linux. They cover malformed/unsafe/duplicate/incomplete manifests, exact XML comparison, complete-subtree structural candidates, unrelated/CDATA/namespace changes, DTD prohibition, truthful result classification, real subprocess stdout/stderr/nonzero-exit/timeout capture, parser/ASCII/CRLF constraints, numeric revision ordering and the actual privacy-safe report writer.

Windows-only ACL/path tests are present but were not executed on Linux. Hosted Windows PowerShell 5.1 CI must execute them before owner delivery is called Windows-verified. Live ESET, non-elevated-controller/UAC interaction and real HIPS enforcement remain owner acceptance; no live ESET testing has occurred here.

Luna read-only review identified ACL inheritance/propagation verification, path rechecks and packaging allowlist concerns. The parent tightened ACL validation and rechecks; packaging begins in a new directory with explicit copies and validates its exact set. The reviewer could not execute tests under its own safety policy. Parent tool output, not child claims, is the test evidence.

`git diff --check` exited 0. The original owner's failed Windows script and error were not provided, so its root cause is NOT DETERMINED.
