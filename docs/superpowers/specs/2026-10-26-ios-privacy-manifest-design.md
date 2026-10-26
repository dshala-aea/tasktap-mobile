# iOS privacy manifest — design

Status: **Implemented in this branch** (`ios/Runner/PrivacyInfo.xcprivacy` + Runner-target wiring).

## Why

App Store uploads are validated against Apple's "required reason API" list. A binary that calls
one of those APIs without a declaration in a `PrivacyInfo.xcprivacy` is flagged at upload
(ITMS-91053, and ITMS-91056 for an invalid manifest) — the build uploads, the review does not
start. The mobile repo had **no manifest at all** (`find . -name PrivacyInfo.xcprivacy` → nothing),
so this was a store blocker with no ticket.

Apple's rule is per *bundle*, not per file: third-party SDKs ship their own manifest and CocoaPods
merges it into the app bundle, but the app's own code and any plugin that does not ship one are
covered only by a manifest the app provides.

## What is declared

`NSPrivacyTracking` is `false` and `NSPrivacyTrackingDomains` is empty: the app has no ATT prompt,
no advertising identifier and no cross-app or cross-site measurement. GPS is a one-shot read at
timbra, never a background track, and nothing goes to an ad or analytics vendor.

The three `NSPrivacyAccessedAPITypes` entries, each tied to the plugin that reaches the API:

| Category | Reason | Reached by |
|---|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` — app reads/writes only its own defaults | `shared_preferences` (onboarding flag, per-user settings, offline-sync toggle) |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` — timestamps of files in the app's own container | `drift` / `sqlite3_flutter_libs` (offline mirror), `path_provider`, `file_picker`, `open_filex`, `share_plus` |
| `NSPrivacyAccessedAPICategoryDiskSpace` | `E174.1` — free space checked when writing or deleting files | same plugins: the sqlite file, downloaded attachments, share temp files |

## What is deliberately not declared

- **`NSPrivacyCollectedDataTypes`.** What the app collects (name, e-mail, worklogs, the GPS of a
  timbra, ticket photos, dictated or recorded audio, absence reasons) is described in the App Store
  Connect privacy questionnaire. A second hand-maintained copy in the bundle would be a declaration
  nothing validates, and it would drift from the questionnaire the first time a field is added —
  the questionnaire is the one Apple publishes and the one a reviewer reads. Add the key only if we
  ever decide to make the in-bundle privacy report authoritative instead.
- **`NSPrivacyAccessedAPICategorySystemBootTime` (`35F9.1`).** The only dependency that reaches
  boot time is `sentry_flutter`'s Cocoa SDK, which ships its own manifest and declares it itself.
  If an upload report ever names this app's bundle for boot-time access, add the entry with
  `35F9.1` — that is the signal to look for, and it is cheap to add then.
- **`ITSAppUsesNonExemptEncryption`** in `Info.plist` is a *separate* export-compliance declaration,
  not part of this manifest, and it is a statement about the crypto the app ships. Worth adding
  (`false`) once the owner confirms there is nothing beyond HTTPS and OS-provided crypto; left out
  here so this change makes no claim it cannot back.

## Wiring

Four entries in `ios/Runner.xcodeproj/project.pbxproj`, mirroring how `GoogleService-Info.plist` is
wired: a `PBXBuildFile`, a `PBXFileReference` (`text.plist.xml`), a child of the `Runner` group, and
an entry in the Resources phase of target `97C146EC1CF9000F007C117D`. A manifest that is on disk but
not in the Resources phase is not in the bundle and nothing fails loudly — which is why the wiring
is part of the change rather than a follow-up.

## Verification, and its limits

- The plist parses (`plistlib.load`) and the three category identifiers are spelled exactly as
  Apple's list spells them — those strings are what the validator matches.
- The four pbxproj references are cross-checked: the build-file id appears twice (definition,
  Resources entry), the file-reference id three times (definition, `fileRef`, group child).
- **It has not been built.** There is no Xcode on this machine, so the `Build iOS` job in
  `.github/workflows/ci.yml` (macOS runner) is the first real proof that the project file still
  opens and the scheme still builds. Merging this without that job going green would be a guess.
- Passing the build does not prove App Review is satisfied: ITMS checks run at upload, on the App
  Store Connect side, and can only be observed by uploading a build.

## Owner actions this unlocks

1. Upload a build and watch for ITMS-91053/91056 on the manifest, and for any boot-time flag (see
   above).
2. Keep the App Store Connect privacy questionnaire in step with the product — it is the source of
   truth for collected data, by design of this change.
3. Decide the export-compliance answer before the next submission (see above).
