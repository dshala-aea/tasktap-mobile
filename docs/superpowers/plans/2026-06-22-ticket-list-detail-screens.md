# D3a — Ticket List + Ticket Detail Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Ticket list screen and Ticket detail screen wired to the real Drift cache, including caching `TicketStatuses` and `TicketTypes` lookup tables that arrive in the sync payload.

**Architecture:** Mirror the dashboard feature pattern — Drift tables for lookups, StreamProviders over `db.select(...).watch()`, `ConsumerWidget` screens. The `TicketStatuses`/`TicketTypes` tables use `int` PK (the same `int` as `statusId`/`typeId` on `Tickets`). Status pills resolve via the existing `statusColor(String)` function; the `Map<int,String>` providers do the int → name bridge. Detail screen uses `AppTabs` with a `StatefulWidget`-level `selectedIndex` so no extra notifier is needed.

**Tech Stack:** Flutter 3.x, Drift (code-gen), Riverpod (StreamProvider / Provider / autoDispose), go_router (StatefulShellRoute), google_fonts (Sora / Manrope), lucide_icons, intl, mocktail (tests).

## Global Constraints

- Italian UI copy everywhere.
- Reuse existing widgets from `lib/core/widgets/` — ScreenHeader, AppSearchBar, AppChip, ListRow, StatusPill, AppBadge, AppCard, KeyVal, SectionTitle, AppTabs, AppFab, EmptyState, AppButton — do NOT rebuild them.
- Theme tokens: `AppColors.DARK/BG1/BG2/BG3/MUTED/DIS/BL/Y/AMBER/WHITE` (already in `lib/core/theme/app_colors.dart`). Status colors via `statusColor(String stato)` in `lib/core/theme/status_colors.dart`.
- Drift codegen artifact `lib/data/local/app_database.g.dart` is gitignored — regenerate but do NOT commit it.
- Each commit message must end with exactly: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- `flutter analyze` must be clean and `flutter test` must stay green (baseline ≥337 tests, must grow).
- ≥44pt touch targets, safe-area aware, 150–300ms transitions.
- Never paste full file contents in responses — reference by path+line.
- Spawn subagents with `model: sonnet`.

---

## File Map

### New files

| File | Responsibility |
|---|---|
| `lib/features/ticket/ticket_providers.dart` | StreamProviders for tickets, status map, type map, schedules-for-ticket |
| `lib/features/ticket/ticket_list_screen.dart` | Ticket list — ScreenHeader, SearchBar, filter chips, ListView of ListRows, FAB |
| `lib/features/ticket/ticket_detail_screen.dart` | Ticket detail — header info, KeyVal card, description, AppTabs with Pianificazioni/EmptyState, bottom actions |
| `test/features/ticket/ticket_providers_test.dart` | Unit tests for providers using in-memory Drift + seeded data |
| `test/features/ticket/ticket_list_screen_test.dart` | Widget tests for list: rows render, filter chip narrows, empty state |
| `test/features/ticket/ticket_detail_screen_test.dart` | Widget tests for detail: KeyVal renders, StatusPill resolves, tabs switch |

### Modified files

| File | Change |
|---|---|
| `lib/data/local/app_database.dart` | Add `TicketStatuses` + `TicketTypes` tables; add to `@DriftDatabase` list; bump `schemaVersion` to 4; add migration step |
| `lib/data/sync/sync_dto.dart` | Add `TicketStatusDto` + `TicketTypeDto`; add fields to `SyncResultDto` + parse in `fromJson` |
| `lib/data/sync/sync_service.dart` | Add `_upsertTicketStatuses` + `_upsertTicketTypes`; call them in `sync()` transaction |
| `lib/core/router/app_router.dart` | Replace `InterventiScreen` with `TicketListScreen` for the ticket branch; add `/ticket/:id` subroute |
| `test/data/sync/sync_service_test.dart` | Extend `_syncPayload` + add tests for `ticketStatuses` + `ticketTypes` parsing and upsert |

---

## Task 1: Drift tables for TicketStatuses + TicketTypes

**Files:**
- Modify: `lib/data/local/app_database.dart`

**Interfaces:**
- Produces: Drift table classes `TicketStatuses` and `TicketTypes`; generated companions `TicketStatusesCompanion` and `TicketTypesCompanion`; accessors `db.ticketStatuses`, `db.ticketTypes`.

- [ ] **Step 1: Add two table classes to `app_database.dart`**

Insert after the `Cantieri` table definition (after line 148, before the `Materiali` comment). The tables must appear before the `@DriftDatabase` annotation uses them:

```dart
// ── ticket_statuses ───────────────────────────────────────────────────────────
class TicketStatuses extends Table {
  IntColumn get id => integer()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── ticket_types ──────────────────────────────────────────────────────────────
class TicketTypes extends Table {
  IntColumn get id => integer()();
  TextColumn get tenantId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: Add both tables to `@DriftDatabase` tables list**

In `app_database.dart`, find the `@DriftDatabase(tables: [...])` annotation (line 342–358). Add `TicketStatuses` and `TicketTypes` to the list after `Cantieri`:

```dart
@DriftDatabase(
  tables: [
    SyncMeta,
    Customers,
    Locations,
    Tickets,
    Schedules,
    Cantieri,
    TicketStatuses,
    TicketTypes,
    Materiali,
    DraftReports,
    ReportStaffTable,
    ReportMateriali,
    ReportControlli,
    ReportAllegati,
    WorkSessions,
  ],
)
```

- [ ] **Step 3: Bump schemaVersion to 4 and add migration step**

In `AppDatabase`, change `schemaVersion => 3` to `schemaVersion => 4`. Add a new `if (from < 4)` block inside `onUpgrade`:

```dart
@override
int get schemaVersion => 4;

@override
MigrationStrategy get migration {
  return MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(draftReports, draftReports.submissionState);
        await m.addColumn(draftReports, draftReports.idempotencyKey);
        await m.addColumn(draftReports, draftReports.submissionError);
      }
      if (from < 3) {
        await m.createTable(workSessions);
      }
      if (from < 4) {
        // D3a: add ticket lookup tables (status + type)
        await m.createTable(ticketStatuses);
        await m.createTable(ticketTypes);
      }
    },
  );
}
```

- [ ] **Step 4: Run Drift codegen**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
cmd.exe /c flutter.bat pub run build_runner build --delete-conflicting-outputs
```

Expected: exits 0, no errors. `app_database.g.dart` is regenerated (gitignored, not committed).

- [ ] **Step 5: Verify analyze is still clean**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
cmd.exe /c flutter.bat analyze
```

Expected: `No issues found.`

- [ ] **Step 6: Commit**

```bash
git add lib/data/local/app_database.dart
git commit -m "$(cat <<'EOF'
feat(D3a): add TicketStatuses + TicketTypes Drift tables (schema v4)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: DTOs + sync service for new lookups

**Files:**
- Modify: `lib/data/sync/sync_dto.dart`
- Modify: `lib/data/sync/sync_service.dart`

**Interfaces:**
- Consumes: `TicketStatuses`/`TicketTypes` Drift table + companions from Task 1.
- Produces: `TicketStatusDto`, `TicketTypeDto` classes with `fromJson`; `SyncResultDto` gains `ticketStatuses` and `ticketTypes` fields; `SyncService` upserts them during `sync()`.

- [ ] **Step 1: Add DTOs to `sync_dto.dart`**

Add after the `TicketDto` class (after line 211, before the `ScheduleDto` comment):

```dart
// ── TicketStatus ───────────────────────────────────────────────────────────────

class TicketStatusDto {
  final int id;
  final String tenantId;
  final String name;
  final bool isDefault;
  final bool isClosed;

  const TicketStatusDto({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.isDefault,
    required this.isClosed,
  });

  factory TicketStatusDto.fromJson(Map<String, dynamic> j) => TicketStatusDto(
        id: (j['id'] as num).toInt(),
        tenantId: j['tenantId'] as String,
        name: j['name'] as String,
        isDefault: j['isDefault'] as bool? ?? false,
        isClosed: j['isClosed'] as bool? ?? false,
      );
}

// ── TicketType ─────────────────────────────────────────────────────────────────

class TicketTypeDto {
  final int id;
  final String tenantId;
  final String name;
  final String? description;

  const TicketTypeDto({
    required this.id,
    required this.tenantId,
    required this.name,
    this.description,
  });

  factory TicketTypeDto.fromJson(Map<String, dynamic> j) => TicketTypeDto(
        id: (j['id'] as num).toInt(),
        tenantId: j['tenantId'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
      );
}
```

- [ ] **Step 2: Add fields to `SyncResultDto`**

In `SyncResultDto`, add two new fields and parse them in `fromJson`. The final class should be:

```dart
class SyncResultDto {
  final DateTime syncedAt;
  final DateTime? since;
  final List<ScheduleDto> schedules;
  final List<ReportDto> draftReports;
  final List<CustomerDto> customers;
  final List<LocationDto> locations;
  final List<TicketDto> tickets;
  final List<TicketStatusDto> ticketStatuses;
  final List<TicketTypeDto> ticketTypes;

  const SyncResultDto({
    required this.syncedAt,
    required this.since,
    required this.schedules,
    required this.draftReports,
    required this.customers,
    required this.locations,
    required this.tickets,
    required this.ticketStatuses,
    required this.ticketTypes,
  });

  factory SyncResultDto.fromJson(Map<String, dynamic> j) {
    return SyncResultDto(
      syncedAt: DateTime.parse(j['syncedAt'] as String),
      since: j['since'] == null ? null : DateTime.parse(j['since'] as String),
      schedules: _list(j['schedules'], ScheduleDto.fromJson),
      draftReports: _list(j['draftReports'], ReportDto.fromJson),
      customers: _list(j['customers'], CustomerDto.fromJson),
      locations: _list(j['locations'], LocationDto.fromJson),
      tickets: _list(j['tickets'], TicketDto.fromJson),
      ticketStatuses: _list(j['ticketStatuses'], TicketStatusDto.fromJson),
      ticketTypes: _list(j['ticketTypes'], TicketTypeDto.fromJson),
    );
  }
}
```

- [ ] **Step 3: Add upsert helpers to `sync_service.dart`**

Add two private methods after `_upsertDraftReports`:

```dart
Future<void> _upsertTicketStatuses(List<TicketStatusDto> list) async {
  for (final s in list) {
    await db.into(db.ticketStatuses).insertOnConflictUpdate(
          TicketStatusesCompanion.insert(
            id: s.id,
            tenantId: s.tenantId,
            name: s.name,
            isDefault: Value(s.isDefault),
            isClosed: Value(s.isClosed),
          ),
        );
  }
}

Future<void> _upsertTicketTypes(List<TicketTypeDto> list) async {
  for (final t in list) {
    await db.into(db.ticketTypes).insertOnConflictUpdate(
          TicketTypesCompanion.insert(
            id: t.id,
            tenantId: t.tenantId,
            name: t.name,
            description: Value(t.description),
          ),
        );
  }
}
```

- [ ] **Step 4: Call them inside the `sync()` transaction**

In the `sync()` method, inside `await db.transaction(() async { ... })`, add two calls after `_upsertDraftReports`:

```dart
await db.transaction(() async {
  await _upsertCustomers(payload.customers);
  await _upsertLocations(payload.locations);
  await _upsertTickets(payload.tickets);
  await _upsertSchedules(payload.schedules);
  await _upsertDraftReports(payload.draftReports);
  await _upsertTicketStatuses(payload.ticketStatuses);
  await _upsertTicketTypes(payload.ticketTypes);
});
```

- [ ] **Step 5: Verify analyze**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
cmd.exe /c flutter.bat analyze
```

Expected: `No issues found.`

- [ ] **Step 6: Commit**

```bash
git add lib/data/sync/sync_dto.dart lib/data/sync/sync_service.dart
git commit -m "$(cat <<'EOF'
feat(D3a): add TicketStatusDto + TicketTypeDto and sync upsert support

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Sync service tests extended for new lookups

**Files:**
- Modify: `test/data/sync/sync_service_test.dart`

**Interfaces:**
- Consumes: `TicketStatusDto`, `TicketTypeDto`, `SyncResultDto` from Task 2; `db.ticketStatuses`, `db.ticketTypes` from Task 1.

- [ ] **Step 1: Add JSON helper functions**

After the `_ticketJson` function in the test file (after line 142), add:

```dart
Map<String, dynamic> _ticketStatusJson({
  int id = 1,
  String name = 'Aperto',
}) =>
    {
      'id': id,
      'tenantId': 'tenant-1',
      'name': name,
      'isDefault': true,
      'isClosed': false,
    };

Map<String, dynamic> _ticketTypeJson({
  int id = 1,
  String name = 'Assistenza',
}) =>
    {
      'id': id,
      'tenantId': 'tenant-1',
      'name': name,
      'description': null,
    };
```

- [ ] **Step 2: Extend `_syncPayload` signature**

The existing `_syncPayload` function (line 32) needs two new optional named params. Add them:

```dart
Map<String, dynamic> _syncPayload({
  DateTime? syncedAt,
  DateTime? since,
  List<Map<String, dynamic>> schedules = const [],
  List<Map<String, dynamic>> draftReports = const [],
  List<Map<String, dynamic>> customers = const [],
  List<Map<String, dynamic>> locations = const [],
  List<Map<String, dynamic>> tickets = const [],
  List<Map<String, dynamic>> ticketStatuses = const [],
  List<Map<String, dynamic>> ticketTypes = const [],
}) {
  return {
    'syncedAt': (syncedAt ?? DateTime.utc(2026, 6, 21, 12)).toIso8601String(),
    'since': since?.toIso8601String(),
    'schedules': schedules,
    'draftReports': draftReports,
    'customers': customers,
    'locations': locations,
    'tickets': tickets,
    'ticketStatuses': ticketStatuses,
    'ticketTypes': ticketTypes,
  };
}
```

- [ ] **Step 3: Add test group for ticketStatuses and ticketTypes**

Add a new group after the existing `'sync — insert new entities'` group:

```dart
group('sync — ticket lookup tables', () {
  test('inserts a new ticketStatus', () async {
    _stubDioGet(
      mockDio,
      _syncPayload(ticketStatuses: [_ticketStatusJson()]),
    );

    await svc.sync();

    final rows = await db.select(db.ticketStatuses).get();
    expect(rows.length, 1);
    expect(rows.first.id, 1);
    expect(rows.first.name, 'Aperto');
    expect(rows.first.isDefault, true);
    expect(rows.first.isClosed, false);
  });

  test('inserts a new ticketType', () async {
    _stubDioGet(
      mockDio,
      _syncPayload(ticketTypes: [_ticketTypeJson()]),
    );

    await svc.sync();

    final rows = await db.select(db.ticketTypes).get();
    expect(rows.length, 1);
    expect(rows.first.id, 1);
    expect(rows.first.name, 'Assistenza');
  });

  test('upserts ticketStatus on re-sync', () async {
    _stubDioGet(mockDio, _syncPayload(ticketStatuses: [_ticketStatusJson(name: 'Vecchio')]));
    await svc.sync();

    _stubDioGet(mockDio, _syncPayload(ticketStatuses: [_ticketStatusJson(name: 'Aggiornato')]));
    await svc.sync();

    final rows = await db.select(db.ticketStatuses).get();
    expect(rows.length, 1);
    expect(rows.first.name, 'Aggiornato');
  });
});
```

- [ ] **Step 4: Extend SyncResultDto parsing test**

In the existing `group('SyncResultDto.fromJson', ...)`, extend the `'parses nested entities'` test to include the new arrays:

```dart
test('parses ticketStatuses and ticketTypes', () {
  final dto = SyncResultDto.fromJson(_syncPayload(
    ticketStatuses: [_ticketStatusJson()],
    ticketTypes: [_ticketTypeJson()],
  ));
  expect(dto.ticketStatuses.length, 1);
  expect(dto.ticketStatuses.first.name, 'Aperto');
  expect(dto.ticketTypes.length, 1);
  expect(dto.ticketTypes.first.name, 'Assistenza');
});
```

- [ ] **Step 5: Run tests**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
cmd.exe /c flutter.bat test test/data/sync/sync_service_test.dart -v
```

Expected: all tests pass. Count should be higher than before.

- [ ] **Step 6: Commit**

```bash
git add test/data/sync/sync_service_test.dart
git commit -m "$(cat <<'EOF'
test(D3a): extend sync_service_test for TicketStatuses + TicketTypes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Ticket providers

**Files:**
- Create: `lib/features/ticket/ticket_providers.dart`

**Interfaces:**
- Consumes: `appDatabaseProvider` from `lib/data/sync/sync_service.dart`; `db.tickets`, `db.ticketStatuses`, `db.ticketTypes`, `db.customers`, `db.locations`, `db.schedules`.
- Produces:
  - `ticketsProvider` → `StreamProvider.autoDispose<List<Ticket>>`
  - `ticketStatusMapProvider` → `StreamProvider.autoDispose<Map<int,String>>`
  - `ticketTypeMapProvider` → `StreamProvider.autoDispose<Map<int,String>>`
  - `ticketByIdProvider` (already exists in `schedule_providers.dart` — import from there, do NOT redefine)

- [ ] **Step 1: Create the providers file**

```dart
// lib/features/ticket/ticket_providers.dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';

/// All cached tickets, most-recent first.
final ticketsProvider = StreamProvider.autoDispose<List<Ticket>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});

/// Map of statusId → Italian status name from cached TicketStatuses table.
final ticketStatusMapProvider =
    StreamProvider.autoDispose<Map<int, String>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.select(db.ticketStatuses).watch().map(
        (rows) => {for (final r in rows) r.id: r.name},
      );
});

/// Map of typeId → type name from cached TicketTypes table.
final ticketTypeMapProvider =
    StreamProvider.autoDispose<Map<int, String>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.select(db.ticketTypes).watch().map(
        (rows) => {for (final r in rows) r.id: r.name},
      );
});

/// All schedules for a specific ticket id.
final schedulesForTicketProvider =
    StreamProvider.autoDispose.family<List<Schedule>, String>((ref, ticketId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.schedules)
        ..where((s) => s.ticketId.equals(ticketId))
        ..orderBy([(s) => OrderingTerm.asc(s.activityDate)]))
      .watch();
});
```

- [ ] **Step 2: Verify analyze**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
cmd.exe /c flutter.bat analyze
```

Expected: `No issues found.`

- [ ] **Step 3: Commit**

```bash
git add lib/features/ticket/ticket_providers.dart
git commit -m "$(cat <<'EOF'
feat(D3a): add ticket Riverpod providers (list, status map, type map, schedules)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Ticket list screen

**Files:**
- Create: `lib/features/ticket/ticket_list_screen.dart`

**Interfaces:**
- Consumes: `ticketsProvider`, `ticketStatusMapProvider`, `ticketTypeMapProvider` from Task 4; `customerByIdProvider`, `locationByIdProvider` from `lib/presentation/providers/schedule_providers.dart`; widgets from `lib/core/widgets/widgets.dart`; `AppColors` from `lib/core/theme/app_colors.dart`; `statusColor` from `lib/core/theme/status_colors.dart`.
- Produces: `TicketListScreen` class; navigates to `/ticket/:id` on row tap.

Filter chip labels and status name matching:
- "Tutti" → no filter
- "Aperti" → statusName.toLowerCase() == 'aperto'
- "In corso" → statusName.toLowerCase() == 'in corso'
- "In attesa" → statusName.toLowerCase() == 'in attesa'
- "Completati" → statusName.toLowerCase() == 'completato'

- [ ] **Step 1: Create `ticket_list_screen.dart`**

```dart
// lib/features/ticket/ticket_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../presentation/providers/schedule_providers.dart';
import 'ticket_providers.dart';

/// Filter options for the ticket list.
enum _TicketFilter { tutti, aperti, inCorso, inAttesa, completati }

extension _TicketFilterLabel on _TicketFilter {
  String get label => switch (this) {
        _TicketFilter.tutti => 'Tutti',
        _TicketFilter.aperti => 'Aperti',
        _TicketFilter.inCorso => 'In corso',
        _TicketFilter.inAttesa => 'In attesa',
        _TicketFilter.completati => 'Completati',
      };

  String? get statusMatch => switch (this) {
        _TicketFilter.tutti => null,
        _TicketFilter.aperti => 'aperto',
        _TicketFilter.inCorso => 'in corso',
        _TicketFilter.inAttesa => 'in attesa',
        _TicketFilter.completati => 'completato',
      };
}

class TicketListScreen extends StatefulWidget {
  const TicketListScreen({super.key});

  @override
  State<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends State<TicketListScreen> {
  _TicketFilter _filter = _TicketFilter.tutti;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: _TicketListBody(
          filter: _filter,
          query: _query,
          searchCtrl: _searchCtrl,
          onFilterChanged: (f) => setState(() => _filter = f),
          onQueryChanged: (q) => setState(() => _query = q),
        ),
      ),
      floatingActionButton: AppFab(
        tooltip: 'Nuovo ticket',
        onPressed: () {
          // TODO(D3b): navigate to new-ticket stub when form is built.
        },
      ),
    );
  }
}

class _TicketListBody extends ConsumerWidget {
  const _TicketListBody({
    required this.filter,
    required this.query,
    required this.searchCtrl,
    required this.onFilterChanged,
    required this.onQueryChanged,
  });

  final _TicketFilter filter;
  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<_TicketFilter> onFilterChanged;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(ticketsProvider);
    final statusMapAsync = ref.watch(ticketStatusMapProvider);

    final statusMap = statusMapAsync.valueOrNull ?? {};
    final allTickets = ticketsAsync.valueOrNull ?? [];

    // Compute counts for subtitle.
    final inCorsoCount = allTickets.where((t) {
      final name = statusMap[t.statusId]?.toLowerCase() ?? '';
      return name == 'in corso';
    }).length;

    // Filter + search.
    final filtered = allTickets.where((t) {
      final statusName = statusMap[t.statusId]?.toLowerCase() ?? '';
      final matchFilter = filter.statusMatch == null ||
          statusName == filter.statusMatch;
      final matchQuery = query.isEmpty ||
          t.title.toLowerCase().contains(query.toLowerCase()) ||
          t.id.toLowerCase().contains(query.toLowerCase());
      return matchFilter && matchQuery;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: 'Ticket',
            subtitle: '${allTickets.length} totali · $inCorsoCount in corso',
            actions: [
              HeaderIconBtn(
                icon: LucideIcons.filter,
                onTap: () {},
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: AppSearchBar(
            controller: searchCtrl,
            hint: 'Cerca ticket…',
            onChanged: onQueryChanged,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _TicketFilter.values.map((f) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppChip(
                      label: f.label,
                      active: filter == f,
                      onTap: () => onFilterChanged(f),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        if (ticketsAsync.isLoading)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            ),
          )
        else if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              icon: LucideIcons.ticketSlash,
              title: 'Nessun ticket',
              body: 'I ticket sincronizzati appariranno qui.',
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final ticket = filtered[i];
                final statusName = statusMap[ticket.statusId] ?? '';
                return _TicketRow(
                  ticket: ticket,
                  statusName: statusName,
                  isLast: i == filtered.length - 1,
                );
              },
              childCount: filtered.length,
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }
}

class _TicketRow extends ConsumerWidget {
  const _TicketRow({
    required this.ticket,
    required this.statusName,
    required this.isLast,
  });

  final Ticket ticket;
  final String statusName;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortId = ticket.id.length > 8 ? ticket.id.substring(0, 8) : ticket.id;
    final dateLabel = DateFormat('dd/MM/yy', 'it').format(ticket.createdAt.toLocal());

    return ListRow(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.BG3,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(LucideIcons.ticket, size: 20, color: AppColors.MUTED),
      ),
      title: ticket.title,
      subtitle: '#$shortId',
      meta: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (statusName.isNotEmpty) StatusPill(stato: statusName, small: true),
          const SizedBox(height: 2),
          Text(
            dateLabel,
            style: const TextStyle(fontSize: 10, color: AppColors.MUTED),
          ),
        ],
      ),
      showDivider: !isLast,
      onTap: () => context.push('/ticket/${ticket.id}'),
    );
  }
}
```

- [ ] **Step 2: Verify analyze**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
cmd.exe /c flutter.bat analyze
```

Expected: `No issues found.`

- [ ] **Step 3: Commit**

```bash
git add lib/features/ticket/ticket_list_screen.dart
git commit -m "$(cat <<'EOF'
feat(D3a): add TicketListScreen with search, filter chips, ListRow per ticket

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Ticket detail screen

**Files:**
- Create: `lib/features/ticket/ticket_detail_screen.dart`

**Interfaces:**
- Consumes: `ticketByIdProvider` from `lib/presentation/providers/schedule_providers.dart`; `ticketStatusMapProvider`, `ticketTypeMapProvider`, `schedulesForTicketProvider` from Task 4; `customerByIdProvider`, `locationByIdProvider` from `lib/presentation/providers/schedule_providers.dart`; all widgets from `lib/core/widgets/widgets.dart`.
- Produces: `TicketDetailScreen({required String ticketId})` class.

Tabs (index 0..4): Report / Controllo / Pianificazioni / Allegati / Fabbisogno. Only Pianificazioni (index 2) shows real cached schedules; all others show EmptyState.

Bottom action: "Cliente" (secondary, no-op) and "Crea rapportino" (primary, routes to `/altro/rapportini/editor/new?ticketId=<ticketId>` or a stub — use `context.push('/altro/rapportini/editor/new')` for now with a TODO comment).

- [ ] **Step 1: Create `ticket_detail_screen.dart`**

```dart
// lib/features/ticket/ticket_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../presentation/providers/schedule_providers.dart';
import 'ticket_providers.dart';

class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<TicketDetailScreen> createState() =>
      _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  int _tabIndex = 0;

  static const _tabs = [
    AppTab(label: 'Report'),
    AppTab(label: 'Controllo'),
    AppTab(label: 'Pianificazioni'),
    AppTab(label: 'Allegati'),
    AppTab(label: 'Fabbisogno'),
  ];

  @override
  Widget build(BuildContext context) {
    final ticketAsync = ref.watch(ticketByIdProvider(widget.ticketId));
    final statusMap = ref.watch(ticketStatusMapProvider).valueOrNull ?? {};
    final typeMap = ref.watch(ticketTypeMapProvider).valueOrNull ?? {};

    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: ticketAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (ticket) {
          if (ticket == null) {
            return SafeArea(
              child: Column(
                children: [
                  ScreenHeader(
                    title: 'Ticket',
                    showBack: true,
                  ),
                  const EmptyState(
                    icon: LucideIcons.ticketX,
                    title: 'Ticket non trovato',
                    body: 'Il ticket richiesto non è disponibile in cache.',
                  ),
                ],
              ),
            );
          }
          return _TicketDetailBody(
            ticket: ticket,
            statusMap: statusMap,
            typeMap: typeMap,
            tabIndex: _tabIndex,
            onTabSelected: (i) => setState(() => _tabIndex = i),
          );
        },
      ),
    );
  }
}

class _TicketDetailBody extends ConsumerWidget {
  const _TicketDetailBody({
    required this.ticket,
    required this.statusMap,
    required this.typeMap,
    required this.tabIndex,
    required this.onTabSelected,
  });

  final Ticket ticket;
  final Map<int, String> statusMap;
  final Map<int, String> typeMap;
  final int tabIndex;
  final ValueChanged<int> onTabSelected;

  static const _tabs = [
    AppTab(label: 'Report'),
    AppTab(label: 'Controllo'),
    AppTab(label: 'Pianificazioni'),
    AppTab(label: 'Allegati'),
    AppTab(label: 'Fabbisogno'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusName = statusMap[ticket.statusId] ?? '';
    final typeName = typeMap[ticket.typeId] ?? '';
    final shortId = ticket.id.length > 8 ? ticket.id.substring(0, 8) : ticket.id;
    final dateLabel = DateFormat('dd/MM/yyyy HH:mm', 'it')
        .format(ticket.createdAt.toLocal());
    final closedLabel = ticket.closedAt != null
        ? DateFormat('dd/MM/yyyy', 'it').format(ticket.closedAt!.toLocal())
        : '—';

    final customerAsync =
        ref.watch(customerByIdProvider(ticket.customerId));
    final locationAsync =
        ref.watch(locationByIdProvider(ticket.locationId));

    final customerName =
        customerAsync.valueOrNull?.companyName ?? ticket.customerId;
    final locationName =
        locationAsync.valueOrNull?.name ?? ticket.locationId;
    final tecnicoLabel = ticket.assignedUserId ?? '—';

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenHeader(
            title: '#$shortId',
            subtitle: ticket.title,
            showBack: true,
          ),

          // Status pill + type chip row
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
            child: Row(
              children: [
                if (statusName.isNotEmpty)
                  StatusPill(stato: statusName),
                if (typeName.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  AppChip(label: typeName, active: false),
                ],
              ],
            ),
          ),

          Expanded(
            child: CustomScrollView(
              slivers: [
                // KeyVal card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(19, 0, 19, 16),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          KeyVal(label: 'Cliente', value: customerName),
                          KeyVal(label: 'Sede', value: locationName),
                          KeyVal(label: 'Tecnico', value: tecnicoLabel),
                          KeyVal(label: 'Data', value: dateLabel),
                          KeyVal(
                            label: 'Chiusura',
                            value: closedLabel,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Descrizione card
                if (ticket.description != null &&
                    ticket.description!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(19, 0, 19, 16),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle(title: 'Descrizione'),
                            const SizedBox(height: 4),
                            Text(
                              ticket.description!,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                color: AppColors.DARK,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Note tecnico card
                if (ticket.technicianNotes != null &&
                    ticket.technicianNotes!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(19, 0, 19, 16),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionTitle(title: 'Note tecnico'),
                            const SizedBox(height: 4),
                            Text(
                              ticket.technicianNotes!,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                color: AppColors.DARK,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Tabs
                SliverToBoxAdapter(
                  child: AppTabs(
                    tabs: _tabs,
                    selectedIndex: tabIndex,
                    onSelected: onTabSelected,
                  ),
                ),

                // Tab content
                SliverToBoxAdapter(
                  child: _TabContent(
                    tabIndex: tabIndex,
                    ticketId: ticket.id,
                  ),
                ),

                const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
              ],
            ),
          ),

          // Bottom actions
          Padding(
            padding: const EdgeInsets.fromLTRB(19, 8, 19, 16),
            child: Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    label: 'Cliente',
                    onPressed: () {
                      // TODO: navigate to customer detail when built (P5).
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Crea rapportino',
                    onPressed: () {
                      // TODO(D3b): navigate to rapportino form with ticketId.
                      // context.push('/altro/rapportini/editor/new?ticketId=${ticket.id}');
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabContent extends ConsumerWidget {
  const _TabContent({required this.tabIndex, required this.ticketId});

  final int tabIndex;
  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (tabIndex) {
      0 => const _EmptyTab(
          icon: LucideIcons.fileText,
          label: 'Nessun rapportino',
          body: 'I rapportini per questo ticket appariranno qui.',
        ),
      1 => const _EmptyTab(
          icon: LucideIcons.clipboardCheck,
          label: 'Nessun controllo',
          body: 'I controlli appariranno qui.',
        ),
      2 => _PianificazioniTab(ticketId: ticketId),
      3 => const _EmptyTab(
          icon: LucideIcons.paperclip,
          label: 'Nessun allegato',
          body: 'Gli allegati caricati appariranno qui.',
        ),
      4 => const _EmptyTab(
          icon: LucideIcons.package,
          label: 'Nessun fabbisogno',
          body: 'I materiali richiesti appariranno qui.',
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({
    required this.icon,
    required this.label,
    required this.body,
  });

  final IconData icon;
  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 0, 19, 0),
      child: EmptyState(icon: icon, title: label, body: body),
    );
  }
}

class _PianificazioniTab extends ConsumerWidget {
  const _PianificazioniTab({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync =
        ref.watch(schedulesForTicketProvider(ticketId));

    return schedulesAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => const _EmptyTab(
        icon: LucideIcons.calendar,
        label: 'Errore caricamento',
        body: 'Impossibile caricare le pianificazioni.',
      ),
      data: (schedules) => schedules.isEmpty
          ? const _EmptyTab(
              icon: LucideIcons.calendarOff,
              label: 'Nessuna pianificazione',
              body: 'Le pianificazioni collegate a questo ticket appariranno qui.',
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(19, 12, 19, 0),
              child: Column(
                children: schedules.map((s) {
                  final dateLabel = DateFormat('EEE d MMM HH:mm', 'it')
                      .format(s.activityDate.toLocal());
                  return ListRow(
                    leading: const Icon(
                      LucideIcons.calendarDays,
                      size: 20,
                      color: AppColors.MUTED,
                    ),
                    title: s.title.isNotEmpty ? s.title : 'Intervento',
                    subtitle: dateLabel,
                    showDivider: s != schedules.last,
                  );
                }).toList(),
              ),
            ),
    );
  }
}
```

- [ ] **Step 2: Verify analyze**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
cmd.exe /c flutter.bat analyze
```

Expected: `No issues found.`

- [ ] **Step 3: Commit**

```bash
git add lib/features/ticket/ticket_detail_screen.dart
git commit -m "$(cat <<'EOF'
feat(D3a): add TicketDetailScreen with KeyVal, AppTabs, Pianificazioni, bottom actions

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Wire router

**Files:**
- Modify: `lib/core/router/app_router.dart`

**Interfaces:**
- Consumes: `TicketListScreen` from `lib/features/ticket/ticket_list_screen.dart`; `TicketDetailScreen` from `lib/features/ticket/ticket_detail_screen.dart`.
- Produces: branch 1 shows `TicketListScreen`; subroute `/ticket/:id` pushes `TicketDetailScreen`.

Note: `AppRoutes.ticket` is already defined as `'/ticket'`. Add `AppRoutes.ticketDetail` for the detail path.

- [ ] **Step 1: Add `ticketDetail` to `AppRoutes`**

In `app_router.dart`, add after `static const String ticket = '/ticket';`:

```dart
static const String ticketDetail = '/ticket/:id';

/// Build the detail path for a given ticket id.
static String ticketDetailPath(String id) => '/ticket/$id';
```

- [ ] **Step 2: Replace the ticket branch with `TicketListScreen` + subroute**

Replace the existing import of `InterventiScreen` with the new imports. Add these imports:

```dart
import '../../features/ticket/ticket_list_screen.dart';
import '../../features/ticket/ticket_detail_screen.dart';
```

Replace branch 1 (`// 1 — Ticket`) with:

```dart
// 1 — Ticket
StatefulShellBranch(
  navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'ticket'),
  routes: [
    GoRoute(
      path: AppRoutes.ticket,
      builder: (context, state) => const TicketListScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => TicketDetailScreen(
            ticketId: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
  ],
),
```

Remove the old import for `InterventiScreen` if it is no longer used anywhere else. Check first:

```bash
grep -r "InterventiScreen" /mnt/d/AEA/Sviluppi/TaskTap/mobile/lib --include="*.dart"
```

If only used in `app_router.dart`, remove the import line `import '../../presentation/screens/interventi/interventi_screen.dart';`.

- [ ] **Step 3: Verify analyze**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
cmd.exe /c flutter.bat analyze
```

Expected: `No issues found.`

- [ ] **Step 4: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "$(cat <<'EOF'
feat(D3a): wire TicketListScreen + detail subroute into app router

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Widget + provider tests for ticket feature

**Files:**
- Create: `test/features/ticket/ticket_providers_test.dart`
- Create: `test/features/ticket/ticket_list_screen_test.dart`
- Create: `test/features/ticket/ticket_detail_screen_test.dart`

**Interfaces:**
- Consumes: all files created in Tasks 1–7; same DB seeding pattern as `test/features/dashboard/`.

### Shared test helpers (copy to each test file that needs them)

```dart
// Seed a ticket into an in-memory DB.
Future<void> seedTicket(
  AppDatabase db, {
  String id = 'ticket-1',
  String title = 'Perdita idrica',
  int statusId = 1,
  int typeId = 1,
  String customerId = 'cust-1',
  String locationId = 'loc-1',
}) async {
  await db.into(db.tickets).insert(TicketsCompanion.insert(
        id: id,
        tenantId: 'tenant-1',
        createdAt: DateTime.utc(2026, 6, 1),
        title: title,
        customerId: customerId,
        locationId: locationId,
        statusId: statusId,
        typeId: typeId,
      ));
}

Future<void> seedTicketStatus(
  AppDatabase db, {
  int id = 1,
  String name = 'Aperto',
}) async {
  await db.into(db.ticketStatuses).insert(TicketStatusesCompanion.insert(
        id: id,
        tenantId: 'tenant-1',
        name: name,
      ));
}

Future<void> seedTicketType(
  AppDatabase db, {
  int id = 1,
  String name = 'Assistenza',
}) async {
  await db.into(db.ticketTypes).insert(TicketTypesCompanion.insert(
        id: id,
        tenantId: 'tenant-1',
        name: name,
      ));
}
```

- [ ] **Step 1: Create `ticket_providers_test.dart`**

```dart
// test/features/ticket/ticket_providers_test.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/ticket/ticket_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('ticketsProvider emits empty list when db empty', () async {
    final result = await container.read(ticketsProvider.future);
    expect(result, isEmpty);
  });

  test('ticketsProvider emits seeded ticket', () async {
    await db.into(db.tickets).insert(TicketsCompanion.insert(
          id: 'ticket-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          title: 'Perdita idrica',
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: 1,
          typeId: 1,
        ));

    final result = await container.read(ticketsProvider.future);
    expect(result.length, 1);
    expect(result.first.title, 'Perdita idrica');
  });

  test('ticketStatusMapProvider emits id→name map', () async {
    await db.into(db.ticketStatuses).insert(TicketStatusesCompanion.insert(
          id: 1,
          tenantId: 'tenant-1',
          name: 'Aperto',
        ));
    await db.into(db.ticketStatuses).insert(TicketStatusesCompanion.insert(
          id: 2,
          tenantId: 'tenant-1',
          name: 'In corso',
        ));

    final result = await container.read(ticketStatusMapProvider.future);
    expect(result[1], 'Aperto');
    expect(result[2], 'In corso');
  });

  test('ticketTypeMapProvider emits id→name map', () async {
    await db.into(db.ticketTypes).insert(TicketTypesCompanion.insert(
          id: 1,
          tenantId: 'tenant-1',
          name: 'Assistenza',
        ));

    final result = await container.read(ticketTypeMapProvider.future);
    expect(result[1], 'Assistenza');
  });

  test('ticketStatusMapProvider returns empty map when no statuses', () async {
    final result = await container.read(ticketStatusMapProvider.future);
    expect(result, isEmpty);
  });

  test('schedulesForTicketProvider returns schedules for matching ticketId',
      () async {
    await db.into(db.schedules).insert(SchedulesCompanion.insert(
          id: 'sched-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          ticketId: const Value('ticket-1'),
          activityDate: DateTime.utc(2026, 7, 1),
          timeStartMinutes: 480,
          timeEndMinutes: 1020,
          userId: 'user-1',
          statusId: 1,
          locationId: 'loc-1',
          title: 'Intervento',
          description: '',
        ));

    // Schedule for a different ticket
    await db.into(db.schedules).insert(SchedulesCompanion.insert(
          id: 'sched-2',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1),
          ticketId: const Value('ticket-2'),
          activityDate: DateTime.utc(2026, 7, 2),
          timeStartMinutes: 480,
          timeEndMinutes: 1020,
          userId: 'user-1',
          statusId: 1,
          locationId: 'loc-1',
          title: 'Altro intervento',
          description: '',
        ));

    final result =
        await container.read(schedulesForTicketProvider('ticket-1').future);
    expect(result.length, 1);
    expect(result.first.id, 'sched-1');
  });
}
```

- [ ] **Step 2: Create `ticket_list_screen_test.dart`**

```dart
// test/features/ticket/ticket_list_screen_test.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/ticket/ticket_list_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}
class MockDio extends Mock implements Dio {}

Widget _buildList({required AppDatabase db, required MockAuthRepository repo}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(MockDio()),
    ],
    child: const MaterialApp(home: TicketListScreen()),
  );
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  final fakeUser = AuthUser(
    id: 'u1',
    email: 'mario@tasktap.io',
    accessToken: 'token',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(fakeUser);
  });

  tearDown(() async {
    authStream.close();
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(_buildList(db: db, repo: repo));
    await tester.pump();
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  group('TicketListScreen', () {
    testWidgets('shows empty state when no tickets', (tester) async {
      await pump(tester);
      expect(find.byType(EmptyState), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders a ListRow per ticket', (tester) async {
      await db.into(db.tickets).insert(TicketsCompanion.insert(
            id: 't1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1),
            title: 'Perdita idrica',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
          ));
      await db.into(db.tickets).insert(TicketsCompanion.insert(
            id: 't2',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 2),
            title: 'Manutenzione caldaia',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 2,
            typeId: 1,
          ));

      await pump(tester);

      expect(find.byType(ListRow), findsNWidgets(2));
      expect(find.text('Perdita idrica'), findsOneWidget);
      expect(find.text('Manutenzione caldaia'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('filter chip narrows list to matching status', (tester) async {
      // Seed a status map
      await db.into(db.ticketStatuses).insert(TicketStatusesCompanion.insert(
            id: 1, tenantId: 'tenant-1', name: 'Aperto'));
      await db.into(db.ticketStatuses).insert(TicketStatusesCompanion.insert(
            id: 2, tenantId: 'tenant-1', name: 'In corso'));

      await db.into(db.tickets).insert(TicketsCompanion.insert(
            id: 't1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1),
            title: 'Ticket aperto',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
          ));
      await db.into(db.tickets).insert(TicketsCompanion.insert(
            id: 't2',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 2),
            title: 'Ticket in corso',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 2,
            typeId: 1,
          ));

      await pump(tester);

      // Tap "In corso" chip
      await tester.tap(find.text('In corso').first);
      await tester.pumpAndSettle();

      expect(find.text('Ticket in corso'), findsOneWidget);
      expect(find.text('Ticket aperto'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows StatusPill with resolved status name', (tester) async {
      await db.into(db.ticketStatuses).insert(TicketStatusesCompanion.insert(
            id: 1, tenantId: 'tenant-1', name: 'Aperto'));
      await db.into(db.tickets).insert(TicketsCompanion.insert(
            id: 't1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1),
            title: 'Un ticket',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
          ));

      await pump(tester);

      expect(find.byType(StatusPill), findsOneWidget);
      expect(find.text('Aperto'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows AppFab', (tester) async {
      await pump(tester);
      expect(find.byType(AppFab), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
```

- [ ] **Step 3: Create `ticket_detail_screen_test.dart`**

```dart
// test/features/ticket/ticket_detail_screen_test.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}
class MockDio extends Mock implements Dio {}

Widget _buildDetail({
  required AppDatabase db,
  required MockAuthRepository repo,
  String ticketId = 'ticket-1',
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(MockDio()),
    ],
    child: MaterialApp(home: TicketDetailScreen(ticketId: ticketId)),
  );
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  final fakeUser = AuthUser(
    id: 'u1',
    email: 'mario@tasktap.io',
    accessToken: 'token',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(fakeUser);
  });

  tearDown(() async {
    authStream.close();
    await db.close();
  });

  Future<void> pump(WidgetTester tester, {String ticketId = 'ticket-1'}) async {
    await tester.pumpWidget(_buildDetail(db: db, repo: repo, ticketId: ticketId));
    await tester.pump();
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  Future<void> seedBase(AppDatabase db) async {
    await db.into(db.ticketStatuses).insert(TicketStatusesCompanion.insert(
          id: 1, tenantId: 'tenant-1', name: 'Aperto'));
    await db.into(db.ticketTypes).insert(TicketTypesCompanion.insert(
          id: 1, tenantId: 'tenant-1', name: 'Assistenza'));
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'cust-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: 'ACME Srl',
        ));
    await db.into(db.locations).insert(LocationsCompanion.insert(
          id: 'loc-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          customerId: 'cust-1',
          name: 'Sede Milano',
        ));
    await db.into(db.tickets).insert(TicketsCompanion.insert(
          id: 'ticket-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 6, 1, 9),
          title: 'Perdita idrica bagno',
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: 1,
          typeId: 1,
          description: const Value('Acqua che perde dal tubo.'),
          assignedUserId: const Value('user-1'),
        ));
  }

  group('TicketDetailScreen', () {
    testWidgets('shows empty-state when ticket not found', (tester) async {
      await pump(tester, ticketId: 'nonexistent');
      expect(find.byType(EmptyState), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders KeyVal rows for Cliente and Sede', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.text('ACME Srl'), findsOneWidget);
      expect(find.text('Sede Milano'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders resolved StatusPill', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.byType(StatusPill), findsOneWidget);
      expect(find.text('Aperto'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders AppTabs with 5 tabs', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.byType(AppTabs), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Pianificazioni'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Pianificazioni tab shows schedules', (tester) async {
      await seedBase(db);
      await db.into(db.schedules).insert(SchedulesCompanion.insert(
            id: 'sched-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1),
            ticketId: const Value('ticket-1'),
            activityDate: DateTime.utc(2026, 7, 10),
            timeStartMinutes: 480,
            timeEndMinutes: 1020,
            userId: 'user-1',
            statusId: 1,
            locationId: 'loc-1',
            title: 'Sopralluogo',
            description: '',
          ));

      await pump(tester);

      // Tap "Pianificazioni" tab (index 2)
      await tester.tap(find.text('Pianificazioni'));
      await tester.pumpAndSettle();

      expect(find.text('Sopralluogo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows bottom action buttons', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.text('Cliente'), findsOneWidget);
      expect(find.text('Crea rapportino'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows description card when description is present',
        (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.text('Acqua che perde dal tubo.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
```

- [ ] **Step 4: Run all tests**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
cmd.exe /c flutter.bat test -v
```

Expected: all tests pass. Test count exceeds 337 (the baseline).

- [ ] **Step 5: Commit**

```bash
git add test/features/ticket/
git commit -m "$(cat <<'EOF'
test(D3a): add widget + provider tests for ticket list, detail, and providers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Final Verification

- [ ] **Run analyze**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
cmd.exe /c flutter.bat analyze
```

Expected: `No issues found.`

- [ ] **Run tests**

```bash
cd /mnt/d/AEA/Sviluppi/TaskTap/mobile
cmd.exe /c flutter.bat test
```

Expected: all tests pass; count > 337.

- [ ] **Confirm gitignored file not committed**

```bash
git status
```

`app_database.g.dart` must not appear in any commit. Confirm with:

```bash
git show --stat HEAD~5..HEAD | grep "app_database.g.dart"
```

Expected: no output.

---

## Self-Review Notes

1. **Spec coverage check:**
   - Task 1–3: TicketStatuses + TicketTypes tables, DTOs, sync ✓
   - Task 4: providers (ticketsProvider, statusMap, typeMap, schedulesForTicket) ✓
   - Task 5: Ticket list — ScreenHeader with "N totali · M in corso", search bar, filter chips (Tutti/Aperti/In corso/In attesa/Completati), ListRow per ticket, FAB, EmptyState ✓
   - Task 6: Ticket detail — short-id + title header, StatusPill + type chip, KeyVal card (Cliente/Sede/Tecnico/Data/Chiusura), Descrizione card, Note tecnico card, AppTabs (5 tabs), Pianificazioni with real schedules, EmptyState for other tabs, bottom buttons (Cliente + Crea rapportino) ✓
   - Task 7: Router — TicketListScreen replaces InterventiScreen, `/ticket/:id` subroute ✓
   - Task 8: Tests — providers, list (rows, filter, empty, FAB), detail (KeyVal, StatusPill, tabs, Pianificazioni, buttons) ✓
   - Sync tests extension ✓

2. **Placeholder scan:** No TBD/TODO-without-context. The "Crea rapportino" button has a TODO comment that is intentional per the spec ("leave navigation seam for D3b").

3. **Type consistency:**
   - `ticketStatusMapProvider` → `Map<int,String>` — consumed in detail and list as `statusMap[ticket.statusId]` (both `int`) ✓
   - `schedulesForTicketProvider` family key is `String` (ticket.id) ✓
   - `TicketStatusesCompanion.insert(id: int, ...)` — `id` is `int` as defined in the table ✓
   - `AppTab` from `lib/core/widgets/app_tabs.dart` — `const AppTab(label: String)` ✓
