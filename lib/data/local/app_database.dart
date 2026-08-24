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

  /// The per-tenant display number the office and the customer use for this job.
  ///
  /// Nullable because tickets created before numbering existed do not have one. Absent means the
  /// ticket has no number — never a reason to fall back to the id.
  TextColumn get numero => text().nullable()();

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

  // Who is on this schedule lives in [ScheduleAssignees]. teamLeadId, staffIds and squadraId
  // were dropped server-side (backend ADR-0009) and stopped arriving; keeping them here would
  // have left three columns that are null forever and a staffIds blob that never parses to
  // anyone — which is the shape that made team-assigned work invisible on the device.

  @override
  Set<Column> get primaryKey => {id};
}

/// Everyone on a schedule, one row per person per reason.
///
/// A row per (schedule, user) rather than a JSON list on Schedules: the list form is what the
/// server just spent a migration removing, and it cannot answer "which of my jobs am I on"
/// without reading every row and parsing each blob.
class ScheduleAssignees extends Table {
  TextColumn get scheduleId => text().references(Schedules, #id)();
  TextColumn get userId => text()();

  BoolColumn get isUserActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isDirect => boolean().withDefault(const Constant(false))();
  BoolColumn get isLead => boolean().withDefault(const Constant(false))();
  BoolColumn get isTeam => boolean().withDefault(const Constant(false))();
  BoolColumn get isLegacyStaff => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {scheduleId, userId};
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
/// The tenant's active users, mirrored so the rapportino staff step can offer a picker.
///
/// Without this table the app had nothing to pick from offline, so the step asked the technician
/// to type a colleague's user id — and invented one when they left it blank. Hours attributed to a
/// fabricated id reach payroll and the customer's invoice.
///
/// Read-only mirror: replaced wholesale on every sync, never written by the device.
class Colleagues extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The tenant's entitlements, mirrored so the app can gate features without a network round trip.
///
/// One row, id `current`. Replaced whole on every successful `/api/Auth/me`; **never cleared on
/// failure** — see `EntitlementRepository` for why that asymmetry is the whole point.
class Entitlements extends Table {
  TextColumn get id => text()();

  /// Granted module keys, JSON array. Mirrors ModuleKeys on the server.
  TextColumn get featuresJson => text()();

  /// Canonical `module.resource.action` keys, JSON array.
  TextColumn get capabilitiesJson => text()();

  /// `field` or `office`. A field seat is the mobile-only seat.
  TextColumn get seatType => text()();

  /// When this was last confirmed by the server. Shown to the user, never used to expire the row.
  DateTimeColumn get fetchedAt => dateTime()();

  /// `Trialing` / `Active` / `PastDue` / `GracePeriod` / `Suspended` / `Canceled` — mirrors the
  /// server's `SubscriptionStatusEnum`. Nullable only for rows written before this column existed;
  /// treated as unknown, not as active, everywhere it is read.
  TextColumn get subscriptionStatus => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

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

  /// GPS/free-text fallback metadata (customerFreeText, locationFreeText, ticketFreeText,
  /// cantiereFreeText, workAddress, gpsLatitude, gpsLongitude) packed as a JSON string.
  ///
  /// Deliberately a separate column from [details]: the editor's autosave used to pack this same
  /// metadata directly into [details], silently overwriting the technician's actual typed
  /// description on every keystroke before it ever reached the backend or the customer-facing
  /// PDF. See ReportEditorNotifier._buildMetadataJson in report_editor_providers.dart.
  TextColumn get metadataJson => text().nullable()();

  TextColumn get insertedUserId => text()();
  TextColumn get locationId => text()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get documentTemplateId => text().nullable()();
  TextColumn get customerSignatureAllegatoId => text().nullable()();
  TextColumn get technicianSignatureAllegatoId => text().nullable()();
  TextColumn get technicianNotes => text().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();

  /// Whether a model produced any of this rapportino's text.
  ///
  /// Persisted on the draft rather than held in memory: a technician generates a draft, closes
  /// the app, comes back an hour later and submits. If the flag lived only in the editor state
  /// the provenance would quietly disappear across that restart, and a report that was in fact
  /// AI-assisted would be filed as hand-written.
  BoolColumn get isAiAssisted => boolean().withDefault(const Constant(false))();

  /// ReportStatoEnum string: Bozza, Inviato, Controllato, Fatturato
  TextColumn get stato => text().withDefault(const Constant('Bozza'))();
  DateTimeColumn get inviatoAt => dateTime().nullable()();
  DateTimeColumn get controllatoAt => dateTime().nullable()();
  TextColumn get controllatoDa => text().nullable()();
  DateTimeColumn get fatturatoAt => dateTime().nullable()();
  BoolColumn get materialiNotRequired => boolean().withDefault(const Constant(false))();
  TextColumn get customerSignoffText => text().nullable()();
  DateTimeColumn get customerSignoffAt => dateTime().nullable()();

  /// True for drafts that only exist locally (not yet submitted).
  BoolColumn get isLocalOnly => boolean().withDefault(const Constant(false))();

  /// Submission state machine:
  /// draft | readyToSubmit | uploadingMedia | submitting | submitted | failed
  TextColumn get submissionState => text().withDefault(const Constant('draft'))();

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
  BoolColumn get isPendingSync => boolean().withDefault(const Constant(true))();

  /// GPS position captured at punch time, for `ingresso`/`ripresa` (interval-opening) events —
  /// null for `fine`/`pausa` and whenever the technician has GPS off or permission was never
  /// granted. Simple timbra still works with no position at all (see cantiere_timbra_screen's own
  /// copy: "La timbratura normale... funziona senza GPS"); this only stops the app from silently
  /// discarding a position it could have captured for free instead of ever sending it. Mirrors the
  /// single "GPS latitude/longitude at punch time" pair `MobileSessionDto` accepts server-side.
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── cantiere_punches (Cantiere Timbra) ────────────────────────────────────────
/// Local-only clock-in / clock-out events for cantiere (worksite) timbratura.
///
/// One row per raw event (mirrors [WorkSessions]), not per session: an
/// 'ingresso' event carries the site context (cantiereId/customerId/ticketId)
/// and the arrival position; the matching 'uscita' event only needs a
/// timestamp. `cantiere_session_assembler.dart` folds pairs of these into the
/// intervals the backend's `/api/CantiereWorkLog/mobile/sessions` upsert
/// expects.
///
/// event_type values:
///   'ingresso' — arrive at site (opens an interval)
///   'uscita'   — leave site (closes the open interval)
class CantierePunches extends Table {
  TextColumn get id => text()();
  DateTimeColumn get eventTime => dateTime()();

  /// One of: ingresso | uscita
  TextColumn get eventType => text()();

  /// Site context — set on 'ingresso', null on 'uscita' (inherited from the
  /// paired opener by the assembler).
  TextColumn get cantiereId => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get ticketId => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();

  /// True while not yet synced to the backend.
  BoolColumn get isPendingSync => boolean().withDefault(const Constant(true))();

  /// Human-readable error message from the last failed sync attempt (null when ok).
  TextColumn get syncError => text().nullable()();

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
  BoolColumn get isDelivered => boolean().withDefault(const Constant(false))();

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

  /// AllegatoEntityTypeEnum: Ticket=0, Report=1, Materiale=2
  IntColumn get entityType => integer()();
  TextColumn get entityId => text()();
  TextColumn get uploadedByUserId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// True when this file has not yet been uploaded to the server.
  BoolColumn get isPendingUpload => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ── pending_tickets ───────────────────────────────────────────────────────────
/// Local outbox for tickets created while the device might be offline.
///
/// Unlike [DraftReports] (which carries a server-honoured idempotency key),
/// ticket creation (`POST /api/Tickets`) has no client-supplied dedup field.
/// So this table's state machine is stricter than the rapportino queue's:
///
///   pendingSync ──(never sent — device was offline at create time)──► submitting
///   submitting  ──(200 OK)──────────────────────────────────────────► submitted
///   submitting  ──(error — outcome on the server is now unknown)────► failed
///
/// `failed` rows are NEVER auto-retried by [TicketCreationQueue.processAll]:
/// the create request may already have reached the server, so resending it
/// automatically could create a duplicate, customer-visible ticket. Only
/// `pendingSync` rows — created while genuinely offline, so the request was
/// never sent at all — are safe to retry automatically on reconnect. A
/// `failed` row requires an explicit, user-initiated retry.
class PendingTickets extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();

  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get customerId => text()();
  TextColumn get locationId => text()();
  TextColumn get assignedUserId => text().nullable()();
  IntColumn get statusId => integer()();
  IntColumn get typeId => integer()();

  /// TicketPriorityEnum: Bassa | Media | Alta | Urgente. Sent on the wire as `priorita`
  /// (backend's `[JsonPropertyName("priorita")]`, string-serialized — see TicketPriorityEnum.cs).
  /// Defaults to "Media" to match the backend's own default when a mobile-created ticket predates
  /// this column or the picker is left untouched.
  TextColumn get priorita => text().withDefault(const Constant('Media'))();

  /// pendingSync | submitting | submitted | failed
  TextColumn get state => text().withDefault(const Constant('pendingSync'))();

  /// Human-readable error from the last failed attempt (null when ok).
  TextColumn get error => text().nullable()();

  /// Set once the server confirms creation — the real Ticket.id.
  TextColumn get serverTicketId => text().nullable()();

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
    ScheduleAssignees,
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
    CantierePunches,
    PendingTickets,
    Colleagues,
    Entitlements,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
      },
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          // M5: add submission state fields to draft_reports
          await m.addColumn(draftReports, draftReports.submissionState);
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
        if (from < 6) {
          // Backend ADR-0009: assignment moved off the Schedules row into its own table.
          // teamLeadId/staffIds/squadraId stopped arriving from the server, so they are
          // dropped rather than left to sit null forever.
          await m.createTable(scheduleAssignees);
          // TableMigration is Drift's supported way to drop a column from SQLite (which has no
          // DROP COLUMN for this case) — it recreates the table from the current definition and
          // copies the rows across. Flagged experimental for API stability, not correctness, and
          // there is no non-experimental alternative short of leaving the dead columns in place.
          // ignore: experimental_member_use
          await m.alterTable(TableMigration(schedules));
        }
        if (from < 7) {
          // Cantiere timbra: add cantiere_punches table for local-first
          // clock-in/out (mirrors work_sessions for the simple timbra flow).
          await m.createTable(cantierePunches);
        }
        if (from < 8) {
          // Offline-first ticket creation: local outbox so a new ticket
          // typed while offline is never silently discarded.
          await m.createTable(pendingTickets);
        }
        if (from < 9) {
          // Rapportino staff step: mirror the tenant's users so a colleague can be
          // picked offline instead of having their user id typed in by hand.
          await m.createTable(colleagues);
        }
        if (from < 10) {
          // B-05: cache entitlements so feature gating survives loss of signal.
          await m.createTable(entitlements);
        }
        if (from < 11) {
          // AI provenance: whether a model wrote any of a draft's text. Defaults to false, which
          // is the honest answer for every rapportino that predates the column.
          await m.addColumn(draftReports, draftReports.isAiAssisted);
        }
        if (from < 12) {
          // The ticket's display number, which the server has been sending all along.
          //
          // Adding the column is not enough on its own: existing rows are null, and the delta
          // cursor means an unchanged ticket is never sent again — so on every device already in
          // the field the number would stay null forever and the UI would keep falling back to a
          // GUID fragment. `syncCursorGeneration` is bumped alongside this for that reason. A new
          // column on a delta-synced table always needs both.
          await m.addColumn(tickets, tickets.numero);
        }
        if (from < 13) {
          // Suspended/canceled tenants keep read access but every write 403s — the app must be
          // able to say why instead of showing an unexplained failure, so subscription status is
          // now cached alongside the rest of the entitlement.
          await m.addColumn(entitlements, entitlements.subscriptionStatus);
        }
        if (from < 14) {
          // Rapportino autosave was packing GPS/free-text metadata into `details` — the same
          // column that holds the technician's actual typed description — silently overwriting
          // it on every keystroke. Splitting metadata into its own column stops the collision;
          // see the doc comment on `DraftReports.metadataJson`.
          await m.addColumn(draftReports, draftReports.metadataJson);
        }
        if (from < 15) {
          // The mobile ticket creation form had no priority field at all — every ticket created
          // from a phone landed at the backend's implicit default with no way to say otherwise.
          await m.addColumn(pendingTickets, pendingTickets.priorita);
        }
        if (from < 16) {
          // Simple attendance punch always sent GPS as null even when a position was available
          // for free (permission already granted). See `WorkSessions.latitude`/`longitude`.
          await m.addColumn(workSessions, workSessions.latitude);
          await m.addColumn(workSessions, workSessions.longitude);
        }
      },
    );
  }

  // ── sync_meta helpers ────────────────────────────────────────────────────

  /// Which generation of the sync cursor this build understands.
  ///
  /// Bumping it makes every existing device do one full sync instead of a delta, and it exists
  /// because a delta cursor can outlive its own correctness. It did: the server's delta filter
  /// compared `UpdatedAt > since` against rows whose `UpdatedAt` is null until someone edits
  /// them, so anything created after a device's last sync was invisible to that device forever.
  /// Fixing the server does not help a phone whose cursor is already past those rows — it will
  /// never ask for them again. Only a full sync recovers, and the technician cannot be asked to
  /// reinstall the app.
  ///
  /// Implemented as part of the row id rather than a new column so it needs no schema migration:
  /// a device on an older generation simply finds no row and syncs from scratch.
  ///
  /// v2 — 2026-08-16, the COALESCE(UpdatedAt, CreatedAt) delta fix.
  /// v3 — 2026-08-17, schema 12 added `tickets.numero`. The column arrives empty and a delta sync
  ///      would never refill it, because the tickets it needs are precisely the ones that have not
  ///      changed. Same reasoning as v2: a cursor can outlive its own correctness.
  static const String syncCursorGeneration = 'v3';

  static const String _cursorId = 'default:$syncCursorGeneration';

  Future<DateTime?> getLastSync() async {
    final row = await (select(syncMeta)
          ..where((t) => t.id.equals(_cursorId)))
        .getSingleOrNull();
    return row?.lastSync;
  }

  Future<void> setLastSync(DateTime dt) async {
    await transaction(() async {
      // Drop cursors from older generations on the way past. They are never read again, and
      // leaving one row per shipped generation to accumulate is the kind of thing nobody notices
      // until there are twelve of them.
      await (delete(syncMeta)..where((t) => t.id.equals(_cursorId).not())).go();
      await into(syncMeta).insertOnConflictUpdate(
        SyncMetaCompanion.insert(id: const Value(_cursorId), lastSync: Value(dt)),
      );
    });
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
