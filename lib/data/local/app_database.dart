// dart format width=100
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Table definitions — mirror the backend sync DTO fields exactly.
// Base fields (id, tenant_id, created_at, updated_at) are replicated on every
// table; no EF navigation properties are stored.
// ══════════════════════════════════════════════════════════════════════════════

// ── sync_meta ─────────────────────────────────────────────────────────────────
/// Single-row table storing the last successful sync timestamp.
class SyncMeta extends Table {
  TextColumn get id => text().withDefault(const Constant('default'))();
  DateTimeColumn get lastSync => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── customers ─────────────────────────────────────────────────────────────────
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get companyName => text()();
  TextColumn get taxId => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get postalCode => text().nullable()();
  TextColumn get country => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get contactPerson => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── locations ─────────────────────────────────────────────────────────────────
class Locations extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get customerId => text()();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get postalCode => text().nullable()();
  TextColumn get country => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── tickets ───────────────────────────────────────────────────────────────────
class Tickets extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get customerId => text()();
  TextColumn get locationId => text()();
  TextColumn get assignedUserId => text().nullable()();
  IntColumn get statusId => integer()();
  IntColumn get typeId => integer()();
  TextColumn get agentId => text().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get technicianNotes => text().nullable()();
  TextColumn get internalNotes => text().nullable()();
  TextColumn get contractId => text().nullable()();
  TextColumn get prodottoAssistenzaId => text().nullable()();
  TextColumn get commessaId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── schedules ─────────────────────────────────────────────────────────────────
class Schedules extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get ticketId => text().nullable()();
  DateTimeColumn get activityDate => dateTime()();
  /// TimeStart stored as total minutes since midnight (TimeSpan has no Drift equivalent)
  IntColumn get timeStartMinutes => integer()();
  /// TimeEnd stored as total minutes since midnight
  IntColumn get timeEndMinutes => integer()();
  TextColumn get userId => text()();
  IntColumn get statusId => integer()();
  TextColumn get locationId => text()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get teamLeadId => text().nullable()();
  /// JSON array of user-id strings
  TextColumn get staffIds => text().withDefault(const Constant('[]'))();
  TextColumn get squadraId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── cantieri ──────────────────────────────────────────────────────────────────
class Cantieri extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get postalCode => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  /// CantiereStatusEnum: Active=0, Completed=1, Cancelled=2
  IntColumn get status => integer().withDefault(const Constant(0))();
  TextColumn get customerId => text().nullable()();
  TextColumn get commessaId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

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

// ── materiali ─────────────────────────────────────────────────────────────────
class Materiali extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get code => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get unitOfMeasure => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get marca => text().nullable()();
  RealColumn get purchasePrice => real().nullable()();
  RealColumn get salePrice => real().nullable()();
  TextColumn get imageUrl => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── draft_reports ─────────────────────────────────────────────────────────────
/// Mirrors Report entity. Holds both server-synced drafts and locally-created ones.
class DraftReports extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get title => text()();
  TextColumn get scheduleId => text().nullable()();
  TextColumn get ticketId => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get details => text().nullable()();
  TextColumn get insertedUserId => text()();
  TextColumn get locationId => text()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get documentTemplateId => text().nullable()();
  TextColumn get customerSignatureAllegatoId => text().nullable()();
  TextColumn get technicianSignatureAllegatoId => text().nullable()();
  TextColumn get technicianNotes => text().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  /// ReportStatoEnum string: Bozza, Inviato, Controllato, Fatturato
  TextColumn get stato => text().withDefault(const Constant('Bozza'))();
  DateTimeColumn get inviatoAt => dateTime().nullable()();
  DateTimeColumn get controllatoAt => dateTime().nullable()();
  TextColumn get controllatoDa => text().nullable()();
  DateTimeColumn get fatturatoAt => dateTime().nullable()();
  BoolColumn get materialiNotRequired =>
      boolean().withDefault(const Constant(false))();
  TextColumn get customerSignoffText => text().nullable()();
  DateTimeColumn get customerSignoffAt => dateTime().nullable()();
  /// True for drafts that only exist locally (not yet submitted).
  BoolColumn get isLocalOnly => boolean().withDefault(const Constant(false))();

  /// Submission state machine:
  /// draft | readyToSubmit | uploadingMedia | submitting | submitted | failed
  TextColumn get submissionState =>
      text().withDefault(const Constant('draft'))();

  /// Stable idempotency key (UUID string) persisted on first submit attempt.
  /// Reused on retries so the server deduplicates duplicate submits.
  TextColumn get idempotencyKey => text().nullable()();

  /// Human-readable error message from the last failed attempt (null when ok).
  TextColumn get submissionError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── report_staff ──────────────────────────────────────────────────────────────
class ReportStaffTable extends Table {
  @override
  String get tableName => 'report_staff';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get reportId => text()();
  TextColumn get userId => text()();
  RealColumn get hoursWorked => real().nullable()();
  RealColumn get kmTraveled => real().withDefault(const Constant(0.0))();
  TextColumn get vehicle => text().nullable()();
  RealColumn get costPerKm => real().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get startTime => dateTime().nullable()();
  DateTimeColumn get endTime => dateTime().nullable()();
  IntColumn get pauseMinutes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── report_materiali ──────────────────────────────────────────────────────────
class ReportMateriali extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get reportId => text()();
  TextColumn get materialeId => text().nullable()();
  TextColumn get freeTextName => text().nullable()();
  RealColumn get quantity => real()();
  TextColumn get unitOfMeasure => text().nullable()();
  RealColumn get unitPrice => real().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get magazzinoId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── report_controlli ──────────────────────────────────────────────────────────
class ReportControlli extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get reportId => text()();
  TextColumn get controlId => text()();
  TextColumn get stringValue => text().nullable()();
  BoolColumn get boolValue => boolean().nullable()();
  DateTimeColumn get dateValue => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── work_sessions (Timbra) ────────────────────────────────────────────────────
/// Local-only clock-in / clock-out sessions for the Timbra feature.
/// When the backend endpoint (D6) is implemented, these rows will be synced up.
///
/// event_type values:
///   'ingresso'  — clock-in (shift start)
///   'fine'      — clock-out (shift end)
///   'pausa'     — pause start
///   'ripresa'   — pause end (resume)
class WorkSessions extends Table {
  @override
  String get tableName => 'work_sessions';

  TextColumn get id => text()();
  DateTimeColumn get eventTime => dateTime()();
  /// One of: ingresso | fine | pausa | ripresa
  TextColumn get eventType => text()();
  /// Optional notes (future use).
  TextColumn get notes => text().nullable()();
  /// True while not yet synced to the backend.
  BoolColumn get isPendingSync =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── notifications ─────────────────────────────────────────────────────────────
/// Cached notifications from the backend. Used for offline display of the
/// notification center. Synced via GET /api/notifications; individual
/// read-state is updated locally and synced back via PUT.
class AppNotifications extends Table {
  @override
  String get tableName => 'notifications';

  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get message => text()();
  /// Notification type string (e.g. TicketAssigned, ScheduleReminder)
  TextColumn get type => text()();
  /// Delivery type string (InApp, Push, Email)
  TextColumn get deliveryType => text()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  DateTimeColumn get readAt => dateTime().nullable()();
  TextColumn get relatedEntityId => text().nullable()();
  TextColumn get relatedEntityType => text().nullable()();
  DateTimeColumn get scheduledFor => dateTime().nullable()();
  DateTimeColumn get sentAt => dateTime().nullable()();
  BoolColumn get isDelivered =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── report_allegati ───────────────────────────────────────────────────────────
/// Local attachment metadata. Before upload, storagePath is a local file path.
class ReportAllegati extends Table {
  TextColumn get id => text()();
  TextColumn get tenantId => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  TextColumn get fileName => text()();
  TextColumn get contentType => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get storagePath => text()();
  TextColumn get url => text()();
  /// AllegatoEntityTypeEnum: Ticket=0, Report=1
  IntColumn get entityType => integer()();
  TextColumn get entityId => text()();
  TextColumn get uploadedByUserId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  /// True when this file has not yet been uploaded to the server.
  BoolColumn get isPendingUpload =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ══════════════════════════════════════════════════════════════════════════════
// Database class
// ══════════════════════════════════════════════════════════════════════════════

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
    AppNotifications,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          // M5: add submission state fields to draft_reports
          await m.addColumn(
              draftReports, draftReports.submissionState);
          await m.addColumn(draftReports, draftReports.idempotencyKey);
          await m.addColumn(draftReports, draftReports.submissionError);
        }
        if (from < 3) {
          // Timbra: add work_sessions table for local clock-in/out (D6 backend pending)
          await m.createTable(workSessions);
        }
        if (from < 4) {
          // D3a: add ticket lookup tables (status + type)
          await m.createTable(ticketStatuses);
          await m.createTable(ticketTypes);
        }
        if (from < 5) {
          // Notifications: add cache table for notification center
          await m.createTable(appNotifications);
        }
      },
    );
  }

  // ── sync_meta helpers ────────────────────────────────────────────────────

  Future<DateTime?> getLastSync() async {
    final row = await (select(syncMeta)
          ..where((t) => t.id.equals('default')))
        .getSingleOrNull();
    return row?.lastSync;
  }

  Future<void> setLastSync(DateTime dt) async {
    await into(syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(id: const Value('default'), lastSync: Value(dt)),
    );
  }
}

// ── Connection factory ────────────────────────────────────────────────────────

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'tasktap.db'));
    return NativeDatabase.createInBackground(file);
  });
}
