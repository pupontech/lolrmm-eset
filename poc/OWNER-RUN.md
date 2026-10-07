# Owner-run Phase 1 preparation — ESET HIPS observation

This guide is for the owner to run on the explicitly selected, isolated ESET Security Ultimate 19.2.x Windows test machine or VM. It does not claim the product/version or any rule mapping is supported. No agent has changed ESET settings or tested ESET enforcement. GitHub Actions only builds and smoke-tests the harmless executable; it cannot prove ESET blocking.

Do not run this on a production or everyday-use computer. Do not disable ESET protection, Self-Defense, or other safeguards. Do not use a wildcard, folder target, broader path, or extra rule to make a test pass. Stop if a screen, rule mapping, or result is ambiguous.

## 1. Confirm the test package and record the environment

1. In the repository’s GitHub Actions page, open a successful run of the POC test-app workflow and download its `LolrmmEsetTest-win-x64.zip` artifact. Do not substitute a source archive, another binary, or an unverified build. Record the run URL, commit, and download date. The Windows CI smoke test does not test ESET.
2. Extract the ZIP into a new, local, non-cloud-synced folder under your user profile, for example `%LOCALAPPDATA%\LOLRMM-POC\<run-date>`. Keep the folder private to your account and administrators. Confirm it contains `LolrmmEsetTest.exe`. Use this exact executable path in the rule; do not point to its parent folder.
3. Create a separate local, non-synced evidence folder with access limited to your account and administrators. Keep all full ESET XML exports and any raw logs/screenshots there. Do not put them in the repository, a cloud-synced directory, or a public issue/chat.
4. Record the date/time and timezone; exact ESET product name and version from ESET’s About page; Windows edition, version, and build from `winver`; whether HIPS is enabled; and whether ESET CMD is enabled and which authorization mode is configured. Do not record or share any ESET password. ESET documents the HIPS status in the product UI and the HIPS settings path; do not change a disabled HIPS setting for this test.[4]
5. Record the full path to the installed `ecmd.exe`. ESET CMD export commands require elevation and the destination folder must already exist; the documented export command is `ecmd /getcfg <path>`. ESET states that export can still work when ESET CMD is disabled, while import requires ESET CMD readiness.[2] Do not disable authorization or change ESET CMD settings just to get an export. If the command is unavailable or fails, record the exact error and stop.

## 2. Export the baseline

1. Open Command Prompt using **Run as administrator**. Run the installed `ecmd.exe` by its full path, quoting paths as needed:

   `"<full path to ecmd.exe>" /getcfg "<full path to evidence folder>\baseline.xml"`

2. Record whether the export succeeded and the filename. Keep `baseline.xml` local and private. Do not paste or upload its contents.

ESET also documents configuration import/export from the product’s Setup menu; this evidence procedure uses the documented elevated ESET CMD export command above.[2][5]

## 3. Add one manual test rule and export it

In the ESET UI, open **Advanced setup → Protections → HIPS → Rules** (or the equivalent HIPS Rules editor in the installed build). Create exactly one new rule with a distinctive name, for example `LOLRMM POC TEST - LolrmmEsetTest`. Before saving, confirm no existing rule with that name is present.

Set the rule manually as follows:

- Action: **Block**; rule enabled.
- Operation: **Start new application**.
- Source applications: **All applications**.
- Application target: **Specific applications**; add the exact path to `LolrmmEsetTest.exe` from step 1. Do not select a folder, wildcard, or additional executable.
- Enable logging severity and user notification; record the exact logging choice shown by the UI.

ESET’s editor documents these rule fields, the `Start new application` operation, logging, notification, all-applications sources, and specific application targets.[1] The proposed source/target mapping above is a **POC hypothesis only**, not a product claim: verify it by the observed behavior and HIPS log. If the installed UI does not offer these choices, stop and record what differs; do not improvise or widen the rule.

After saving the rule, export the configuration with the same elevated `ecmd.exe` command, changing the output filename to `with-manual-rule.xml`. Keep the full XML local and private.

## 4. Test and record the block, log, and notification

1. Launch the exact `LolrmmEsetTest.exe` once as your normal user. Do not run it elevated. Record whether it ran or was blocked, the time, any visible notification, and the exact rule name shown. Do not infer a block from a missing console window alone.
2. In ESET, open **Tools → Log files**, choose the **HIPS** log, and check for an entry at the test time. Record whether the application, prohibited result, and test rule name appear. ESET documents the HIPS log fields and that only rules marked for recording appear there.[3]
3. If it runs, the expected HIPS entry is absent, the rule name/result is unclear, or anything unexpected occurs, stop. Record the outcome; do not change filtering mode, add another rule, or broaden the target.

## 5. Remove only the test rule and prove the executable runs again

1. Reopen HIPS Rules and locate only the exact rule you created (`LOLRMM POC TEST - LolrmmEsetTest`). Confirm its name and exact executable target, then remove that one rule. Do not remove or edit any other ESET rule or setting.
2. Export the post-removal configuration as `after-removal.xml` using the same elevated `/getcfg` command. Keep it local. Do not import any XML during this preparation procedure.
3. Launch the same executable again as your normal user. Record that it prints `Test Application` and exits normally (exit code 0). If it does not, stop and report the exact result; do not adjust other ESET settings.
4. Confirm the named manual test rule is absent in the HIPS Rules editor. Preserve the three exports locally for the owner’s comparison. The later Phase 1 work must still establish XML preservation, programmatic insertion, official signing if required, import/re-export verification, idempotency, and live block/unblock acceptance; this manual observation alone does not pass that gate.

## Safe evidence handling and stop conditions

- Keep full XML exports, unsanitized logs, and screenshots on the secured local machine. Never upload or commit them, and never send ESET passwords, password prompts, or configuration files containing unrelated personal settings.
- If analysis is needed, share only a **sanitized HIPS rule diff**: the relevant test-rule entries and the minimum surrounding structure needed to understand them. Remove unrelated settings/rules, machine/account identifiers, and private paths; replace the user-specific portion of the executable path consistently while preserving the path structure needed for review. Do not share a full XML export.
- Report product/Windows version, HIPS/ESET CMD readiness, artifact run/commit, command success or exact error, rule settings, observed block/run result, notification result, and HIPS log result. Do not include secrets.
- Stop on any failed export, missing/disabled HIPS, unknown prompt, unexpected block, failure to remove only the manual rule, or unclear source/target behavior. Do not widen rules to improve coverage.

## Sources

[1] https://help.eset.com/esu/19/en-US/idh_hips_editor_single_rule.html — ESET Security Ultimate 19 HIPS rule settings
[2] https://help.eset.com/esu/19/en-US/idh_config_ecmd.html — ESET Security Ultimate 19 ESET CMD
[3] https://help.eset.com/esu/19/en-US/idh_page_logs.html — ESET Security Ultimate 19 Log files
[4] https://help.eset.com/esu/19/en-US/idh_hips_main.html — ESET Security Ultimate 19 HIPS overview
[5] https://help.eset.com/esu/19/en-US/idh_importexport_config.html — ESET Security Ultimate 19 Import and export settings
