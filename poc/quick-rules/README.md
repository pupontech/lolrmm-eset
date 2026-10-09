# ESET Quick Rules - experimental owner-run POC

This is a small append-only test utility, NOT a certified ESET integration. The first test targets only the harmless bundled LolrmmEsetTest.exe. It does not download the LOLRMM catalog, create AV exclusions/allow/firewall rules, install a service/task, disable protection or remove anything.

## First owner test

1. Use an isolated Windows client machine with consumer ESET major 19. Extract the complete Windows CI test ZIP into a fresh private local folder, not a synced/network folder or the ZIP viewer. Verify the ZIP checksum and source provenance. Do not overlay an old kit.
2. Do NOT double-click the test EXE: it prints one line and exits, so its window would close immediately. In File Explorer, open the extracted folder, type `cmd` in the address bar and press Enter (do NOT run as administrator). In that terminal run `LolrmmEsetTest.exe`, then `echo %errorlevel%`. Expect `Test Application` and `0`. Keep that NON-ELEVATED terminal open for the later block/unblock checks. The injector must not run the test EXE elevated.
3. Double-click `START-HERE.bat`. UAC opens one elevated console for Preview. Preview exports/backs up configuration and displays ADD/UNCHANGED names and exact target paths; it does not import. Check that the target is this copy of the harmless EXE.
4. Confirm HIPS is enabled in ESET. Configure ESET CMD for Advanced setup password authorization; do not use unauthenticated import or weaken Self-Defense. The tool does not guess readiness from generic XML names or turn protection/settings on.
5. Run `START-HERE.bat -Apply`. Acknowledge the isolated test machine, approve same-account UAC, review the exact names/paths, and type APPLY only if intended. ESET's official signer prompts for the setup password; enter it there, never in chat, CSV, arguments or logs. The tool may stage the signer from ESET's official URL and verifies its publisher before use.
6. Read the private result. A successful import/readback is NOT proof of blocking. From the NON-ELEVATED terminal, try the harmless EXE again. Confirm a matching denied HIPS event for the exact generated rule/path/time and record notification behavior. A different launch failure is not proof of ESET blocking.
7. Re-run Apply with unchanged input. Expect UNCHANGED/no import/no duplicate. This is the owner-live idempotency check, not merely a fixture-test claim.
8. In ESET HIPS Rules, remove ONLY the exact new `LOLRMM Block - LolrmmEsetTest - <path suffix>` rule displayed by the script. Do not restore a whole old configuration blindly. Run the harmless EXE normally again; expect `Test Application` and exit 0. Check unrelated rules/settings survived.

If import, timeout or verification fails, configuration state may be unknown. Inspect ONLY the exact displayed names and manually clean up only the rules created in this run. No unattended rollback is claimed. Keep these instructions available if the console is closed.

## Minimal input

`rules.csv` has exactly `Name,Path` columns. The bundled input is:

```csv
Name,Path
LolrmmEsetTest,.\LolrmmEsetTest.exe
```

That one special relative test path resolves beside the script. Other inputs must be exact absolute Windows .exe paths. Wildcards, environment expansions, UNC/device paths, traversal, alternate streams, generic Windows executables and malformed CSV are rejected. Paths are deduplicated case-insensitively. A same managed name with conflicting semantics stops; the tool never edits/removes administrator rules. Omitting a row does not remove an existing rule.

After harmless native acceptance only, a chosen product can be represented by an explicit exact path. Do not claim this blocks renamed/moved binaries or all LOLRMM products.

## Invocation and exits

```text
START-HERE.bat                 non-mutating live preview
START-HERE.bat -Apply          explicit isolated-machine import experiment
START-HERE.bat -ValidateOnly   package check; no ESET access
```

Direct PowerShell is available for debugging. Live calls require elevation; the launcher handles a single UAC child per run. Offline preview works without ESET:

```powershell
.\Eset-QuickRules.ps1 -RulesFile .\rules.csv -ConfigurationFile 'C:\Private-ESET\existing-export.xml'
```

Private run artifacts live under `%LOCALAPPDATA%\LOLRMM-QuickRules\runs\<unique run>`. Keep raw XML, diagnostics and native-command output local. Do not upload exports or passwords. `RESULTS.txt`, if produced, is the fixed-message sharing summary; inspect it before sharing. The script's exit 0/1 reports its own operation outcome, not native Phase 1 acceptance. The full gate remains OWNER_PENDING/UNVERIFIED until the owner supplies block/log/unblock, preservation and rerun evidence.

## Why this format is experimental

ESET's current KB7375 links a minimal consumer HIPS XML using APPEND=1. Its sample is an accessibility ALLOW rule with an old home wrapper; it is not imported by this tool. A real consumer 15.0.18 export supplies action=2 and Application_Create=1 on named deny-child-process rules. The proposed all-sources/exact-target composition and current-build append/identifier behavior remain unverified. A same-shape v19 export is a prerequisite for the experiment, NOT proof that it will enforce correctly.

The utility retains private backup, known ownership, exact-target safety, official signing, concurrency checks and re-export verification. It does not silently strip fields named timestamp/modified or claim a hidden difference is harmless. Legitimate volatile changes can therefore stop/mark verification unresolved; report that result rather than weakening checks.

Official sources:
- https://support.eset.com/en/kb7375-allow-screen-readers-access-to-eset-gui
- https://help.eset.com/esu/19/en-US/idh_config_ecmd.html
- https://help.eset.com/esu/19/en-US/idh_hips_editor_single_rule.html

The self-contained x64 test EXE requires no .NET SDK on the owner machine. The batch launcher uses Windows PowerShell 5.1. Source/fixture and hosted Windows proof remain distinct from actual ESET evidence. This is an owner test artifact, not a licensed production release.
