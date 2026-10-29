# Rapportino work segments — mobile implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the phone records the technician's real work intervals, sends them with the rapportino, mirrors back what the office or another device wrote, and stops letting a typed number disagree with the taps that produced it.

**Architecture:** a new Drift child table `report_staff_segments` keyed by `(report_id, user_id)`, exactly like the server's `ReportStaffSegment`. `StaffRow` carries the list; `ReportEditorNotifier.stopTimer` appends to it; `SubmissionQueue` sends it; the sync applier replaces it per report. The Ore field becomes a read-only readout once intervals exist.

**Tech Stack:** Flutter, Riverpod, Drift, `flutter_test`.

**Spec:** `../api-report-segments/docs/superpowers/specs/2026-10-29-rapportino-work-segments-design.md` §Mobile (backend merged to `tasktap-api` `master` as `93b6ed6e`). The api plan is `2026-10-29-rapportino-work-segments.md` in the same api checkout.

## Global Constraints

- **Never run `dart format`.** It rewrites eleven files into tall style for a ten-line change and CI has no format gate. Files that opt in already carry `// dart format width=100` at the top; match the surrounding style by hand.
- **Do not run the whole test suite in one foreground command** if it takes minutes; the owner interrupts long waits. Run the affected test files first, the full suite once at the end.
- The device clock is not authoritative for segment times: store UTC instants (`DateTime.now().toUtc()`), never Rome wall-clock labels.
- Every wire key the app reads must exist on the server, and for `Sync*` DTOs the key sets must match **exactly** in both directions (`test/contract/sync_inbound_contract_test.dart`).
- Local schema steps are **linear**, one number per release. Current head is 59; this plan takes 60.
- A new column or child collection on a delta-synced table needs `syncCursorGeneration` bumped, because a device with a cursor only receives rows that changed since.

---

### Task 1: Refresh the contract snapshot

**Files:**
- Modify: `test/contract/openapi.snapshot.json`

**Interfaces:**
- Consumes: nothing.
- Produces: a snapshot declaring `SyncReportSegmentDto`, `SyncReportStaffDto.segments`, `SyncReportStaffDto.hoursSource`, `SubmitReportSegmentDto` and `SubmitReportStaffDto.segments`. Everything after this task is checked against it.

- [ ] **Step 1: Download the merged snapshot**

```bash
cd /root/tt-worktrees/mobile-report-segments
curl -sSL "$(gh api 'repos/dshala-aea/tasktap-api/contents/docs/api/openapi.snapshot.json?ref=master' --jq '.download_url')" \
  -o test/contract/openapi.snapshot.json
```

- [ ] **Step 2: Prove the new schemas are in the file**

```bash
/usr/bin/grep -o '"SyncReportSegmentDto"' test/contract/openapi.snapshot.json | wc -l
```
Expected: at least `1` — the schema declaration plus any inline references.

- [ ] **Step 3: Run the inbound contract test**

Run: `flutter test test/contract/sync_inbound_contract_test.dart`
Expected: **FAIL** with "the server declares fields the app never reads: add them or consciously drop them" for `SyncReportStaffDto`. That failure is the signal Task 3 exists; do not edit the DTO in this task, and do not treat it as a regression.

- [ ] **Step 4: Commit**

```bash
git add test/contract/openapi.snapshot.json
git commit -m "chore(contract): refresh the OpenAPI snapshot after the report-segments merge"
```

---

### Task 2: The `report_staff_segments` table, schema 60, cursor v17

**Files:**
- Modify: `lib/data/local/app_database.dart` (table class, `@DriftDatabase` list, `schemaVersion`, `onUpgrade`, index helper, `syncCursorGeneration`)
- Create: `test/data/local/migration_v60_test.dart`

**Interfaces:**
- Produces: `ReportStaffSegments` Drift table, SQL table `report_staff_segments` with columns `id`, `tenant_id`, `created_at`, `updated_at`, `report_id`, `user_id`, `start_utc`, `end_utc`, `client_id`; generated `ReportStaffSegmentData` and `ReportStaffSegmentsCompanion`; `AppDatabase.schemaVersion == 60`, `AppDatabase.syncCursorGeneration == 'v17'`.

- [ ] **Step 1: Write the failing migration test**

Create `test/data/local/migration_v60_test.dart`, following `migration_v59_test.dart`'s shape (`Directory.systemTemp`, `NativeDatabase(file)`, `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true`):

```dart
// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';

/// Schema 59 -> 60: the technician's real work intervals.
///
/// A NEW table, so `createTable` is additive on its own and Drift emits
/// `CREATE TABLE IF NOT EXISTS`, which also keeps the older-schema fixtures working when they
/// rewind `user_version` on a current-schema database.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('tasktap_mig60_');
    file = File('${dir.path}/app.sqlite');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<bool> hasTable(AppDatabase db, String table) async =>
      (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
                variables: [Variable.withString(table)],
              )
              .get())
          .isNotEmpty;

  test('a 59 database gains report_staff_segments', () async {
    // A current-schema database rewound to 59 — the device-before-upgrade shape the other
    // migration tests use, and the shape that would die on a table that already exists if the
    // step used a bare CREATE TABLE.
    final db = AppDatabase(NativeDatabase(file));
    await db.customStatement('PRAGMA user_version = 59');
    await db.customStatement('DROP TABLE report_staff_segments');
    await db.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    expect(await hasTable(upgraded, 'report_staff_segments'), isTrue);
    await upgraded.close();
  });

  test('the new table round-trips a segment, client id included', () async {
    final db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.reportStaffSegments)
        .insert(
          ReportStaffSegmentsCompanion.insert(
            id: 'seg-1',
            tenantId: 't1',
            createdAt: DateTime.utc(2026, 10, 29, 8),
            reportId: 'report-1',
            userId: 'user-1',
            startUtc: DateTime.utc(2026, 10, 29, 7),
            endUtc: DateTime.utc(2026, 10, 29, 9),
            clientId: const Value('seg-1'),
          ),
        );
    final rows = await db.select(db.reportStaffSegments).get();
    expect(rows.single.startUtc, DateTime.utc(2026, 10, 29, 7));
    expect(rows.single.clientId, 'seg-1');
    await db.close();
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/data/local/migration_v60_test.dart`
Expected: FAIL — `reportStaffSegments` is not defined on `AppDatabase`.

- [ ] **Step 3: Add the table class**

In `lib/data/local/app_database.dart`, immediately after `class ReportStaffTable` (around line 910):

```dart
// ── report_staff_segments ─────────────────────────────────────────────────────
/// One work interval of one technician on one report — what the timer actually recorded.
///
/// Mirrors the server's `ReportStaffSegment`: it hangs off `(reportId, userId)` exactly like the
/// `report_staff` row it describes, and carries the phone's own id for the tap in [clientId] so a
/// replayed submit collapses onto the rows it already wrote instead of counting the hours twice.
class ReportStaffSegments extends Table {
  @override
  String get tableName => 'report_staff_segments';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get reportId => text()();
  TextColumn get userId => text()();

  /// The run's real instants, UTC.
  DateTimeColumn get startUtc => dateTime()();
  DateTimeColumn get endUtc => dateTime()();

  /// The phone's id for this tap, stable across a retried submit. Null for an interval that only
  /// ever came down from the server for a row written by an older client.
  TextColumn get clientId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 4: Register it**

Add `ReportStaffSegments,` to the `@DriftDatabase(tables: [...])` list (near `ReportStaffTable`). Bump `int get schemaVersion => 59;` to `60`.

- [ ] **Step 5: Add the migration step**

In `onUpgrade`, immediately after the `if (from < 59)` block:

```dart
        if (from < 60) {
          // The technician's real work intervals — one row per start/stop, the thing the
          // rapportino's hours are supposed to be. `report_staff` gets no new column: exactly as
          // server-side, segments are a child collection of the staff row.
          //
          // A NEW table, so `createTable` is additive on its own and drift emits
          // `CREATE TABLE IF NOT EXISTS`, which keeps the older-schema fixtures working when they
          // rewind `user_version` on a current-schema database (the `from < 52`/`53`/`54`
          // branches' reasoning).
          //
          // The cursor bump to v17 is NOT optional here: report children travel inside the report
          // aggregate, and `MobileUserSyncService` delta-filters reports on
          // `(UpdatedAt ?? CreatedAt) > cutoff` exactly like everything else. A device whose
          // cursor already sits past a report would never receive that report's intervals until
          // somebody touched it, so every rapportino already on the phone would open with no
          // segments at all and the Ore field would stay editable on a timer row.
          await m.createTable(reportStaffSegments);
          await _createReportStaffSegmentIndexes();
        }
```

- [ ] **Step 6: Add the index helper**

Next to `_createChecklistIndexes` (around line 2585), and call it from `onCreate` as well:

```dart
  /// Intervals are read per report (the editor) and per report+technician (the submit payload and
  /// any later correction), never by id alone.
  Future<void> _createReportStaffSegmentIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS report_staff_segments_report '
      'ON report_staff_segments (report_id, user_id)',
    );
  }
```

- [ ] **Step 7: Bump the cursor generation**

Change `static const String syncCursorGeneration = 'v16';` to `'v17'` and append the ledger comment above it, in the same voice as the v12–v16 entries:

```dart
  /// v17 — 2026-10-29, schema 60 added `report_staff_segments`. The intervals travel inside the
  ///      report aggregate, which is delta-filtered by report, so a device whose cursor already
  ///      sits past a report would never receive that report's segments — every rapportino already
  ///      on the phone would open with an empty interval list. Same blind spot as
  ///      v3/v4/v6/v8/v10/v12/v13/v15. Bumping the generation only invalidates the cursor; the
  ///      reports themselves are re-requested and arrive whole with their children.
```

- [ ] **Step 8: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `app_database.g.dart` regenerates with `ReportStaffSegments`, `ReportStaffSegmentData`, `ReportStaffSegmentsCompanion`, and `reportStaffSegments` on `AppDatabase`.

- [ ] **Step 9: Run the tests**

Run: `flutter test test/data/local/migration_v60_test.dart test/data/local/migration_v59_test.dart`
Expected: all PASS.

- [ ] **Step 10: Commit**

```bash
git add lib/data/local/app_database.dart lib/data/local/app_database.g.dart test/data/local/migration_v60_test.dart
git commit -m "feat(db): store a report's work intervals on the device (schema 60)"
```

---

### Task 3: Read the intervals back from the server

**Files:**
- Modify: `lib/data/sync/sync_dto.dart` (`SyncReportStaffDto`, new `SyncReportSegmentDto`)
- Modify: `lib/data/sync/sync_service.dart` (the report-aggregate block, around line 1117)
- Modify: `test/contract/sync_inbound_contract_test.dart` (register the new DTO)
- Modify: the report-aggregate apply test — find it with `/usr/bin/grep -rln "reportStaff" test/`

**Interfaces:**
- Consumes: `reportStaffSegments` from Task 2.
- Produces: `SyncReportSegmentDto { id, tenantId, createdAt, updatedAt, reportId, userId, startUtc, endUtc, clientId }` with `wireKeys`; `SyncReportStaffDto.segments` (`List<SyncReportSegmentDto>`) and `SyncReportStaffDto.hoursSource` (`int`).

- [ ] **Step 1: Make the contract test fail by registering the DTO**

In `test/contract/sync_inbound_contract_test.dart`, add to `readKeys`:

```dart
    // The technician's real work intervals, mirrored so a report resumed on another device — or
    // re-opened after a reinstall — still knows what the timer recorded. Child of the staff row,
    // carried inside the report aggregate.
    'SyncReportSegmentDto': SyncReportSegmentDto.wireKeys,
```

Run: `flutter test test/contract/sync_inbound_contract_test.dart`
Expected: FAIL — `SyncReportSegmentDto` is not defined.

- [ ] **Step 2: Add the DTO**

In `lib/data/sync/sync_dto.dart`, after `SyncReportStaffDto`:

```dart
/// One work interval of a `SyncReportStaffDto` — the mirror of the server's
/// `SyncReportSegmentDto`, and the reason a rapportino shows the hours the timer recorded instead
/// of the span from first start to last stop.
class SyncReportSegmentDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String reportId;
  final String userId;
  final DateTime startUtc;
  final DateTime endUtc;

  /// The phone's own id for the tap, when this interval originated on a device that sent one.
  final String? clientId;

  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'createdAt',
    'updatedAt',
    'reportId',
    'userId',
    'startUtc',
    'endUtc',
    'clientId',
  };

  const SyncReportSegmentDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.reportId,
    required this.userId,
    required this.startUtc,
    required this.endUtc,
    this.clientId,
  });

  factory SyncReportSegmentDto.fromJson(Map<String, dynamic> j) => SyncReportSegmentDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    reportId: j['reportId'] as String,
    userId: j['userId'] as String,
    startUtc: DateTime.parse(j['startUtc'] as String),
    endUtc: DateTime.parse(j['endUtc'] as String),
    clientId: j['clientId'] as String?,
  );
}
```

- [ ] **Step 3: Extend `SyncReportStaffDto`**

Add the two fields, their `wireKeys` entries (`'hoursSource'`, `'segments'`), and in `fromJson`:

```dart
        hoursSource: _intOrNull(j['hoursSource']) ?? 0,
        segments: _list(j['segments'], SyncReportSegmentDto.fromJson),
```

with the field docs:

```dart
  /// Where this row's hours come from: `Legacy` (0), `Timer` (1), `Manual` (2). Carried so the UI
  /// can say why a number is what it is; the editor's own read-only rule keys off the presence of
  /// [segments], which is the fact the technician can see and the timer wrote.
  final int hoursSource;

  /// The intervals recorded for this row, oldest first. Always a list, empty when none.
  final List<SyncReportSegmentDto> segments;
```

- [ ] **Step 4: Mirror them in the applier**

**The segments are nested, not a sibling list.** The server projects them separately but stitches
them into each `SyncReportStaffDto` before serializing (`MobileUserSyncService.cs:681-695`), and
`MobileUserSyncResult` has no `reportSegments` member — only `ReportStaff`. So there is no new
payload property to add: `payload.reportStaff` already carries them, once `SyncReportStaffDto`
parses `segments` in Step 3.

In `lib/data/sync/sync_service.dart`'s report-aggregate block, delete the table for `replace` beside
the other children, then insert each staff row's own intervals right after that row:

```dart
        await (db.delete(
          db.reportStaffSegments,
        )..where((g) => g.reportId.isIn(replace))).go();
```

```dart
          for (final g in s.segments) {
            await db
                .into(db.reportStaffSegments)
                .insert(
                  ReportStaffSegmentsCompanion.insert(
                    id: g.id,
                    tenantId: g.tenantId,
                    createdAt: g.createdAt,
                    updatedAt: Value(g.updatedAt),
                    reportId: reportId,
                    userId: g.userId,
                    startUtc: g.startUtc,
                    endUtc: g.endUtc,
                    clientId: Value(g.clientId),
                  ),
                );
          }
```

Place it inside the existing `for (final s in staff[reportId] ...)` loop, immediately after that
row's `reportStaffTable` insert, so a reader sees the row and the intervals that justify its hours
in one place.

The delete for `report_staff_segments` keys on `replace`, exactly like `reportStaffTable` and the
other children, and runs in the same delete batch — a report in the payload's in-scope set with no
segments genuinely has none, and the local-only working copy is already excluded by `owned`.

- [ ] **Step 5: Run the contract and sync tests**

Run: `flutter test test/contract/sync_inbound_contract_test.dart test/data/sync/`
Expected: PASS. The contract test now passes in both directions, which is the proof the key names match the server exactly.

- [ ] **Step 6: Commit**

```bash
git add lib/data/sync/sync_dto.dart lib/data/sync/sync_service.dart test/contract/sync_inbound_contract_test.dart test/data/sync/
git commit -m "feat(sync): mirror a report's work intervals back onto the phone"
```

---

### Task 4: The timer records intervals

**Files:**
- Modify: `lib/presentation/providers/report_editor_providers.dart` (`StaffRow`, `stopTimer`, `_hydrateBody`, `removeStaff`)
- Modify: `lib/data/reports/draft_report_repository.dart` (segment read/write/delete)
- Modify: `test/presentation/providers/report_editor_providers_test.dart`

**Interfaces:**
- Consumes: `reportStaffSegments` (Task 2).
- Produces: `StaffRow.segments` (`List<StaffSegment>`), `StaffSegment { String id; DateTime startUtc; DateTime endUtc; }`; `DraftReportRepository.getSegments(String reportId)`, `upsertSegments(List<ReportStaffSegmentsCompanion>)`, `deleteSegmentsForStaff(String reportId, String userId)`.

- [ ] **Step 1: Write the failing tests**

In `test/presentation/providers/report_editor_providers_test.dart`, using the file's existing notifier harness:

```dart
  test('stopTimer records the interval it just measured', () async {
    // A stop is evidence: the run's two instants are what the server bills from. The accumulated
    // `hoursWorked` alone cannot say when the technician stopped for lunch.
    // start → stop
    final stored = await repo.getSegments(reportId);
    expect(stored, hasLength(1));
    expect(stored.single.endUtc.isAfter(stored.single.startUtc), isTrue);
  });

  test('two runs record two intervals, not one span', () async {
    // start/stop, start/stop — the gap between them is not worked time.
    expect(await repo.getSegments(reportId), hasLength(2));
  });
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/presentation/providers/report_editor_providers_test.dart`
Expected: FAIL — `getSegments` is not defined.

- [ ] **Step 3: Add the model**

In `report_editor_providers.dart`, above `StaffRow`:

```dart
/// One recorded work interval, as the device holds it.
///
/// [id] doubles as the wire `clientId`: it is the phone's own name for this tap, so a replayed
/// submit collapses server-side instead of counting the hours twice.
class StaffSegment {
  const StaffSegment({required this.id, required this.startUtc, required this.endUtc});

  final String id;
  final DateTime startUtc;
  final DateTime endUtc;

  Duration get duration => endUtc.difference(startUtc);
}
```

`StaffRow` gains `final List<StaffSegment> segments;` (default `const []`), threaded through `copyWith`.

- [ ] **Step 4: Make `effectiveHours` believe the intervals**

```dart
  /// Effective hours: the sum of the recorded intervals when there are any, else `hoursWorked`,
  /// else the timer's start→end span minus pauses.
  double get effectiveHours {
    if (segments.isNotEmpty) {
      final minutes = segments.fold<int>(0, (sum, s) => sum + s.duration.inMinutes);
      return minutes / 60.0;
    }
    if (hoursWorked != null) return hoursWorked!;
    ...
  }
```

- [ ] **Step 5: Record on stop**

```dart
  /// Stop on-screen timer, record the interval, and recompute hoursWorked from the intervals.
  Future<void> stopTimer(String staffId) async {
    final row = state.staffRows.firstWhere((r) => r.id == staffId);
    final now = DateTime.now().toUtc();
    final startedAt = row.timerStartedAt;
    final newSegments = startedAt == null
        ? row.segments
        : [
            ...row.segments,
            StaffSegment(
              // A UUID, not a readable `seg-<epoch>`: the server binds `Id` and `ClientId` as
              // `Guid`, so any other string fails to deserialize and the whole submit 400s. The
              // local id and the claimed `ClientId` are the same value, so a replayed tap
              // collapses onto the row it already wrote instead of recording the hours twice.
              id: const Uuid().v4(),
              startUtc: startedAt,
              endUtc: now,
            ),
          ];
    final stopped = row.copyWith(
      timerRunning: false,
      endTime: now,
      segments: newSegments,
      clearTimer: true,
    );
    await updateStaff(
      newSegments.isEmpty ? stopped : stopped.copyWith(hoursWorked: stopped.effectiveHours),
    );
    await _repo.upsertSegments([
      for (final s in newSegments)
        ReportStaffSegmentsCompanion.insert(
          id: s.id,
          tenantId: state.tenantId,
          createdAt: DateTime.now().toUtc(),
          reportId: state.reportId,
          userId: row.userId,
          startUtc: s.startUtc,
          endUtc: s.endUtc,
          clientId: Value(s.id),
        ),
    ]);
  }
```

Hours are still written on the row, derived from the intervals: the office web and every older client read that column.

- [ ] **Step 6: Persist and hydrate**

`DraftReportRepository`:

```dart
  /// Oldest first: a staff row's intervals are read positionally by the submit slice.
  Future<List<ReportStaffSegment>> getSegments(String reportId) => (_db.select(
    _db.reportStaffSegments,
  )..where((s) => s.reportId.equals(reportId))
   ..orderBy([(s) => OrderingTerm.asc(s.startUtc)])).get();

  /// Upsert only the rows the caller just created. Rewriting a hydrated row would overwrite the
  /// server's own `clientId` and `createdAt` with this device's values, and the claimed idempotency
  /// key would stop matching the interval the server already holds.
  Future<void> upsertSegments(List<ReportStaffSegmentsCompanion> rows) async {
    await _db.batch((b) => b.insertAllOnConflictUpdate(_db.reportStaffSegments, rows));
  }

  /// Intervals belong to `(reportId, userId)`, so removing the technician removes their taps —
  /// a re-added colleague must not inherit the previous person's intervals.
  Future<void> deleteSegmentsForStaff(String reportId, String userId) async {
    await (_db.delete(
      _db.reportStaffSegments,
    )..where((s) => s.reportId.equals(reportId) & s.userId.equals(userId))).go();
  }
```

`_hydrateBody` loads `final segments = await _repo.getSegments(draft.id);`, groups them by `userId`, and gives each staff row its own list. `removeStaff` calls `deleteSegmentsForStaff`. The report-delete path (`draft_report_repository.dart` ~line 66, "delete every child of this report") must delete its segments too.

- [ ] **Step 7: Run the tests**

Run: `flutter test test/presentation/providers/report_editor_providers_test.dart`
Expected: PASS, including the two new tests.

- [ ] **Step 8: Commit**

```bash
git add lib/presentation/providers/report_editor_providers.dart lib/data/reports/draft_report_repository.dart test/presentation/providers/report_editor_providers_test.dart
git commit -m "feat(rapportino): the timer records real intervals, not just a running total"
```

---

### Task 5: The Ore field stops disagreeing with the timer

**Files:**
- Modify: `lib/features/rapportino/steps/step_ore.dart`
- Modify: the widget test that owns these assertions — `/usr/bin/grep -rln "StepOre" test/`

**Interfaces:**
- Consumes: `StaffRow.segments`, `StaffRow.effectiveHours` (Task 4).

- [ ] **Step 1: Write the failing widget test**

```dart
  testWidgets('a technician with recorded intervals sees the timer total, not an editable Ore', (
    tester,
  ) async {
    // Two one-hour intervals with a gap between them: the row must read 2,0 h — not the 4 h span.
    expect(find.text('2,0'), findsOneWidget);
    expect(find.text('Ore'), findsNothing); // the Ore box is gone; Km stays
  });
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/features/rapportino/`
Expected: FAIL — the Ore field is still editable.

- [ ] **Step 3: Make the field a readout when intervals exist**

In `_StaffTileState.build`, the Ore field becomes conditional on `row.segments.isEmpty`; otherwise render a `_ReadOnlyHours(hours: row.effectiveHours, segmentCount: row.segments.length)` widget in the same footprint, with one line of explanation:

> *"Calcolate dal timer: le ore non sono modificabili perché il timer ha registrato gli orari."*

Keep the Km field editable and keep the `didUpdateWidget` resync for the editable branch.

- [ ] **Step 4: The worklog suggestion cannot write what the field cannot**

The same tile has a second writer `_staffToCompanion` (`report_editor_providers.dart:1415`) will clobber:
the worklog-suggestion apply. When the row has intervals, applying a suggestion must not silently set
`hoursWorked` and then have the row's own derived total overwrite it on the next save. Either hide the
apply action for a row with intervals, or make it clear the intervals first (a deliberate manual
override, `deleteSegmentsForStaff` then `copyWith(segments: const [], hoursWorked: …)`), and say in one
line which you chose and why. A technician who overrides a timer with a suggestion is making a manual
correction — that is the reading this plan expects, so prefer clearing over hiding, and let the Ore
field become editable again in the same gesture.

- [ ] **Step 5: Fix the span readout and the stale claim**

`totalOre` already folds `effectiveHours`, which now sums intervals — verify with the same test. Keep
the "Inizio / Fine" line, and append the interval count to "Ore effettive" when there is more than one:

```dart
'Ore effettive: ${row.effectiveHours.toStringAsFixed(2)}h'
'${row.segments.length > 1 ? ' · ${row.segments.length} intervalli' : ''}'
```

`step_ore.dart:310-313` claims `effectiveHours` "prefers that range over `hoursWorked` whenever both
are set". That was already false before this plan and is false in a different way now. Rewrite it to
the precedence that actually holds — intervals, then `hoursWorked`, then the span minus pauses.

- [ ] **Step 6: Run the tests**

Run: `flutter test test/features/rapportino/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/rapportino/steps/step_ore.dart test/features/rapportino/
git commit -m "feat(rapportino): the Ore field reads the timer instead of competing with it"
```

---

### Task 6: Send the intervals

**Files:**
- Modify: `lib/data/reports/submit_report_request.dart` (`SubmitReportStaffDto`, new `SubmitReportSegmentDto`)
- Modify: `lib/data/sync/submission_queue.dart` (the staff mapping at ~line 493)
- Modify: `test/contract/openapi_contract_test.dart`
- Modify: `test/data/sync/submission_queue_test.dart`

**Interfaces:**
- Consumes: the submit wire shape, which is **not** the sync shape: `startTime`, `endTime`, `clientId` only.
- Produces: `SubmitReportSegmentDto { DateTime startTime; DateTime endTime; String? clientId; }` and `SubmitReportStaffDto.segments`.

- [ ] **Step 1: Write the failing tests**

Contract — extend `fullRequest`'s one staff row with a segment, then:

```dart
    test('SubmitReportStaffDto sends no field the server does not have', () {
      final json = (fullRequest.toJson()['staff'] as List).first as Map<String, dynamic>;
      expectNoUnknownKeys('SubmitReportStaffDto', json);
      final segment = (json['segments'] as List).first as Map<String, dynamic>;
      expectNoUnknownKeys('SubmitReportSegmentDto', segment);
    });
```

Queue — a report whose staff row has two stored intervals produces two segments, each carrying its local id as `clientId`.

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/contract/openapi_contract_test.dart test/data/sync/`
Expected: FAIL — no `segments` property.

- [ ] **Step 3: Add the DTOs**

```dart
/// One recorded work interval. Mirror of backend `SubmitReportSegmentDto`: the two instants and
/// the phone's own id for the tap. The id is what makes a retried submit a no-op instead of a
/// double-billed second set of hours.
class SubmitReportSegmentDto {
  const SubmitReportSegmentDto({required this.startTime, required this.endTime, this.clientId});

  final DateTime startTime;
  final DateTime endTime;
  final String? clientId;

  Map<String, dynamic> toJson() => {
    'startTime': startTime.toUtc().toIso8601String(),
    'endTime': endTime.toUtc().toIso8601String(),
    if (clientId != null) 'clientId': clientId,
  };
}
```

`SubmitReportStaffDto` gains `final List<SubmitReportSegmentDto> segments;` (default `const []`) and in `toJson`:
`if (segments.isNotEmpty) 'segments': segments.map((s) => s.toJson()).toList(),` — omitted when empty, which the server reads as "not timer-recorded", exactly the pre-segments wire shape.

- [ ] **Step 4: Send them from the queue**

In `submission_queue.dart` the staff rows already come from Drift; load `db.reportStaffSegments` for `draft.id` beside them, group by `userId`, and pass, oldest first (`ORDER BY start_utc`):

```dart
              segments: [
                for (final g in segmentsByUser[s.userId] ?? const <ReportStaffSegmentsData>[])
                  SubmitReportSegmentDto(
                    startTime: g.startUtc,
                    endTime: g.endUtc,
                    clientId: g.clientId,
                  ),
              ],
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/contract/ test/data/sync/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/data/reports/submit_report_request.dart lib/data/sync/submission_queue.dart test/contract/openapi_contract_test.dart test/data/sync/
git commit -m "feat(submit): send the recorded intervals with the rapportino"
```

---

### Task 7: Whole-suite verification

- [ ] **Step 1: Analyze**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 2: Full suite, in the background if it is slow**

Run: `flutter test`
Expected: all PASS. Record the counts in the ledger.

- [ ] **Step 3: Push**

```bash
git push -u origin feat/report-staff-segments
```

The owner merges; only `main` deploys, and mobile CI runs on PRs against `main`.
