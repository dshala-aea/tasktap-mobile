# Worker Digital Badge — Mobile (v1, online-only) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A technician shows a rotating badge QR in the app; a team leader scans technicians' badges at a cantiere and sees the outcome per worker.

**Architecture:** A `BadgeApiClient` (Dio, same style as `CantiereWorklogApiClient`) over the merged backend (api #181): `GET /api/badge/me`, `POST /api/cantieri/{id}/badge-scan`. A badge screen under Altro refreshes the token on a timer; a continuous scanner (new, because `BarcodeScanSheet` pops after the first code) feeds scans to the API and lists result cards. **Online-only in v1** (owner-approved): the token is server-signed, so neither phone verifies anything offline.

**Tech Stack:** Flutter, Riverpod, go_router, Dio, `qr_flutter` + `mobile_scanner` (already dependencies), `wakelock_plus` (new, one small plugin).

**Spec:** `docs/superpowers/specs/2026-10-28-worker-badge-design.md` in the **tasktap-api** repo (merged; the binding authority). Backend contract: api PR #181, `docs/api/openapi.snapshot.json` on api `master`.

## Global Constraints

- **Online-only.** No offline badge, no offline scan queue, no Drift tables in v1. When offline, say so plainly and do nothing else.
- **Token handling:** the QR payload is the raw token string from `GET /api/badge/me`; never logged, never persisted, never put in a URL. Valid 60s and **single-use once accepted**: the screen must refresh at most every ~25s and must fetch a fresh token each time the screen is opened or resumed.
- **Scan requests always carry a `ClientScanId`** (new random UUID v4 per scan attempt; reused only when retrying the same attempt).
- **Result handling is closed:** every `BadgeScanResult` value the backend can send is mapped to a defined card; an unknown value maps to `unknown` (never a crash, never a silent success).
- **Wire format:** `BadgeScanResult` and `BadgeScanAction` arrive as **names** (strings), not integers.
- **Leader gate in the UI** reuses `isLeadForCantiereProvider`; the server still enforces (403 `NotLead`).
- No `dart format` (rewrites unrelated files; CI has no format gate). No local `flutter test` assumption: if `fvm flutter` is runnable in your shell, run the named tests; otherwise do a static review (every identifier, import and type cross-checked) and rely on CI. Tests that touch widgets: labels are `Text.rich` + uppercase (use `findRichText`), scope sheet finders to the BottomSheet, slivers build lazily.
- Contract gate: the four mobile contract tests are `test/contract/openapi_contract_test.dart`, `request_body_contract_test.dart`, `sync_inbound_contract_test.dart`, `sync_request_contract_test.dart`, plus `test/data/api/response_shape_contract_test.dart`. **Name them explicitly** when running (a directory run silently skips some).
- Italian UI copy; accessibility: result cards announce via `Semantics(liveRegion: true)`; large tap targets (gloved, sunlit, one-handed field conditions).

## Review Focus

- `GET /api/badge/me` → 409 `badge_revoked` / `user_inactive` shows a clear "Badge disattivato — contatta l'ufficio" state, never a retry loop. (Task 2)
- Offline / timeout / 5xx on refresh: the screen shows an offline state and **hides the old QR** (a stale QR must never look valid). (Task 2)
- App backgrounded and resumed: the QR is replaced by a fresh token before it is shown again; timers cancelled on dispose/background. (Task 2)
- A scan result of `Replayed` / `Expired` / `NotAssigned` / `OpenElsewhere` / `PayrollLocked` / `Revoked` / `Invalid` / unknown each renders its own non-success card. (Task 3)
- The same QR in frame for several frames produces ONE request (debounce per code), and the next worker can be scanned without reopening the camera. (Task 3)
- A non-lead never sees the entry point; a 403 `NotLead` from the server shows a clear message. (Task 3)

---

### Task 1: Contract sync, DTOs and `BadgeApiClient`

**Files:**
- Modify: `test/contract/openapi.snapshot.json` (re-sync from api `master`; leaf-diff, do not trust counts — fix only drift that touches DTOs this app consumes, list any other drift in the report)
- Create: `lib/data/badge/badge_models.dart`, `lib/data/badge/badge_api_client.dart`
- Test: `test/data/badge/badge_models_test.dart`, `test/data/badge/badge_api_client_test.dart`; extend `test/contract/request_body_contract_test.dart` / `test/data/api/response_shape_contract_test.dart` for the two new shapes

**Interfaces:**
- Produces:
  - `enum BadgeScanResult { accepted, notAssigned, revoked, expired, invalid, openElsewhere, payrollLocked, replayed, unknown }` with `static BadgeScanResult fromWire(String? v)` (case-insensitive name match; null/unrecognised → `unknown`).
  - `enum BadgeScanAction { none, opened, closed, unknown }` with `fromWire`.
  - `class BadgeCard { String badgeId; String token; int expiresInSeconds; String displayName; String? photoUrl; String employerName; String status; }` + `factory BadgeCard.fromJson(Map<String,dynamic>)` (keys: `badgeId, token, expiresInSeconds, displayName, photoUrl, employerName, status`).
  - `class BadgeWorker { String displayName; String? photoUrl; String employerName; }`
  - `class BadgeScanOutcome { BadgeScanResult result; BadgeScanAction action; String? workLogId; BadgeWorker? worker; }` + `fromJson` (keys `result, action, workLogId, worker`).
  - `class BadgeApiException implements Exception { int? statusCode; String? code; String message; bool get isRevoked; bool get isInactive; bool get isNotLead; bool get isOffline; }`.
  - `class BadgeApiClient { BadgeApiClient(Dio dio); Future<BadgeCard> getMyBadge(); Future<BadgeScanOutcome> scan({required String cantiereId, required String token, required String clientScanId}); }` plus `final badgeApiClientProvider = Provider<BadgeApiClient>(...)` following how `cantiereWorklogApiClientProvider` is built. `getMyBadge` maps 409 body `code`/`error` `badge_revoked` → `isRevoked`, `user_inactive` → `isInactive`; `scan` maps 403 `{error:"NotLead"}` → `isNotLead`; connection/timeout errors → `isOffline`.

- [ ] **Step 1: Re-sync the snapshot** — copy api master's `docs/api/openapi.snapshot.json` (read it via `gh api repos/dshala-aea/tasktap-api/contents/docs/api/openapi.snapshot.json?ref=master`, never a local api ref) over `test/contract/openapi.snapshot.json`; run the five contract tests by explicit file name; leaf-diff old vs new and record what changed beyond the badge additions.
- [ ] **Step 2: Write failing tests** `badge_models_test.dart`: `BadgeScanResult_fromWire_MapsEveryBackendName` (the 8 names + `Replayed`), `fromWire_UnknownAndNull_AreUnknown`, `BadgeCard_fromJson_ParsesAllFields_NullPhoto`, `BadgeScanOutcome_fromJson_WorkerNull_ForInvalid`; `badge_api_client_test.dart` (fake Dio adapter as other api-client tests do): `getMyBadge_409_BadgeRevoked_IsRevoked`, `getMyBadge_409_UserInactive_IsInactive`, `getMyBadge_Timeout_IsOffline`, `scan_SendsClientScanIdAndToken_ToCantiereRoute`, `scan_403_NotLead_IsNotLead`; contract tests assert the request body keys (`token`, `clientScanId`) match the snapshot's `BadgeScanRequest` and the response keys match `BadgeCard`/`BadgeScanOutcome`.
- [ ] **Step 3: Run** the named tests → FAIL (types missing).
- [ ] **Step 4: Implement** per the interfaces; file header comment in the repo's `// ═══` style stating the endpoints, like `CantiereWorklogApiClient`.
- [ ] **Step 5: Run** the named tests and the five contract tests → PASS (or static review if flutter is not runnable; say which).
- [ ] **Step 6: Commit** `feat(badge): badge api client, models and contract sync`

### Task 2: "Il mio badge" screen

**Files:**
- Create: `lib/features/badge/my_badge_screen.dart`, `lib/features/badge/badge_providers.dart`
- Modify: `lib/core/router/app_router.dart` (add `AppRoutes.altroBadge = '/altro/badge'` + route), `lib/features/altro/altro_hub_screen.dart` (a tile "Il mio badge" in the personal section next to "I miei dati"), `pubspec.yaml` (+ `wakelock_plus`)
- Test: `test/features/badge/my_badge_screen_test.dart`

**Interfaces:**
- Consumes: `badgeApiClientProvider`, `BadgeCard`, `BadgeApiException` (Task 1); `QrImageView` as in `kiosk_display_screen.dart`.
- Produces: `class MyBadgeScreen extends ConsumerStatefulWidget { const MyBadgeScreen({super.key}); }`; `sealed class BadgeViewState { loading, ready(BadgeCard card, DateTime fetchedAt), revoked, inactive, offline, error(String message) }` and `badgeControllerProvider` (`AutoDisposeNotifier<BadgeViewState>` or the repo's equivalent) exposing `refresh()`; the controller refreshes every **25s** while the screen is visible (inject the interval for tests), cancels on dispose and on app pause, and re-fetches on resume before showing a QR.

- [ ] **Step 1: Write failing widget tests** (override `badgeApiClientProvider` with a fake): `shows_photo_name_employer_and_qr_when_ready`; `no_photo_shows_initials_placeholder`; `revoked_409_shows_disattivato_message_no_qr_no_retry_loop`; `inactive_shows_account_disattivato`; `offline_hides_qr_and_shows_offline_notice`; `refreshes_token_on_interval` (fake async timer, second fetch replaces the QR data); `resume_refetches_before_showing_qr`; `uses_semantics_for_status`. Assert on the QR's `data` string, not pixels.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** screen + controller + route + Altro tile; enable `WakelockPlus` while the screen is mounted and release on dispose; no brightness plugin (v1 decision). Large QR on a white card regardless of theme (scan reliability), `Semantics(liveRegion: true)` for state changes.
- [ ] **Step 4: Run** → PASS (or static review).
- [ ] **Step 5: Commit** `feat(badge): il mio badge screen with rotating QR`

### Task 3: Leader continuous scan and result cards

**Files:**
- Create: `lib/core/scanner/continuous_scan_view.dart` (continuous scanner widget), `lib/features/badge/badge_scan_screen.dart`, `lib/features/badge/badge_scan_result_card.dart`, `lib/features/badge/badge_scan_controller.dart`
- Modify: `lib/features/timbra/cantiere_timbra_screen.dart` (a "Scansiona badge" entry visible only when `isLeadForCantiereProvider` is true), `lib/core/router/app_router.dart` (route `/timbra/cantiere/:id/badge-scan` or the repo's equivalent naming)
- Test: `test/features/badge/badge_scan_screen_test.dart`, `badge_scan_result_card_test.dart`

**Interfaces:**
- Consumes: `BadgeApiClient.scan`, `BadgeScanOutcome`, `BadgeApiException` (Task 1); `MobileScanner` as in `lib/core/scanner/barcode_scan_sheet.dart` (read it; the new widget keeps the camera open).
- Produces:
  - `typedef ScanSource = Widget Function(BuildContext, void Function(String code) onCode);` injectable so tests drive scans without a camera; the default builds the `MobileScanner` view.
  - `class BadgeScanScreen extends ConsumerStatefulWidget { const BadgeScanScreen({super.key, required this.cantiereId, this.scanSource}); final String cantiereId; }`
  - `class BadgeScanController` (Riverpod notifier) with `Future<void> onCode(String code)`: ignores a code equal to the last handled code for 3s and ignores new codes while a request is in flight; generates a `clientScanId` per attempt; appends a `BadgeScanEntry { DateTime at; BadgeScanOutcome? outcome; BadgeApiException? error }` to a session list (newest first, in memory only).
  - `BadgeScanResultCard(BadgeScanEntry entry)` renders by closed mapping (Italian): accepted+opened "ENTRATA registrata", accepted+closed "USCITA registrata", accepted+none "Già registrato"; `notAssigned` "Non assegnato a questo cantiere — segnalato all'ufficio"; `revoked` "Badge non valido — contatta l'ufficio"; `expired` "Badge scaduto — chiedi di riaprire il badge"; `replayed` "Codice già usato — chiedi di aggiornare il badge"; `invalid` "Codice non riconosciuto"; `openElsewhere` "Ha un turno aperto su un altro cantiere"; `payrollLocked` "Periodo paghe chiuso — contatta l'ufficio"; `unknown` "Risposta non riconosciuta — riprova". Success is green with a check icon AND text; every non-success has an icon AND text (never colour alone); worker photo/name when `worker != null`; `NotLead` error "Solo il capo squadra può scansionare"; offline "Nessuna connessione — riprova".

- [ ] **Step 1: Write failing tests**: controller — `same_code_in_frame_sends_one_request`, `next_code_scans_without_reopening`, `in_flight_ignores_new_codes`, `each_attempt_has_unique_clientScanId`; each outcome mapping (a theory over all `BadgeScanResult` values) renders the expected Italian text and a non-success icon for everything but accepted; `unknown_result_never_renders_as_success`; `notlead_403_shows_message`; `offline_shows_message_and_allows_retry`; widget — `entry_point_hidden_for_non_lead`, `entry_point_opens_scanner_for_lead`; the screen lists scanned workers newest first.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the continuous scan view (no pop on detect; `MobileScannerController` disposed on leave; formats limited to QR), controller, card, screen, entry point, route. Keep the camera preview visible above the result list so the leader keeps aiming.
- [ ] **Step 4: Run** → PASS (or static review).
- [ ] **Step 5: Commit** `feat(badge): team leader continuous badge scan with result cards`

---

## Self-review notes

- Spec coverage (mobile slice): badge screen with photo/name/employer + rotating QR (T2); revoked/inactive states (T2); leader scan with per-outcome cards, flag-and-record visibility (`NotAssigned`), single-use handling (`Replayed`/`Expired`) (T3); `ClientScanId` always sent (T1/T3). **Not in this plan (by decision):** offline badge/scan, offline roster cache, the web admin, the audit export.
- Backend-client notes carried from the api review: tokens are single-use and valid 60s, so each presentation needs a fresh token; offline scans arriving later than 60s would be `Expired` (the future offline plan decides how to handle that).
- Brightness control is deliberately absent (adds a second plugin for little value); wake lock is included.
