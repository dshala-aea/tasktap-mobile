import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/app_database.dart';
import '../../data/reports/cantiere_report_api_client.dart';
import '../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../presentation/providers/auth_providers.dart';
import '../../presentation/providers/report_editor_providers.dart'
    show draftReportRepositoryProvider;

const _uuid = Uuid();

/// Creates a local rapportino draft with the identifiers this device actually knows.
///
/// ## What was wrong, stated accurately
///
/// Two screens created drafts with `tenantId: 'local'` and `insertedUserId: 'local-user'`,
/// duplicated between them. It is worth being precise about the damage, because the obvious
/// reading overstates it: **neither value is ever transmitted.** `SubmitReportRequest` carries no
/// tenant and no author, the attachment upload posts only the file, and the server derives both
/// from the bearer token. So these literals never reached payroll or an invoice.
///
/// What they did do:
///
/// 1. **Named nobody on screen.** `rapportino_view_screen` falls back to `insertedUserId` for the
///    technician line when a draft has no staff rows, so a real report displayed the string
///    `local-user` as the person who wrote it.
/// 2. **Left a trap in the table.** Sync writes real tenant ids into `draft_reports`, so the table
///    holds a mix of genuine ids and the literal `local`. Nothing filters on it *today* — the day
///    someone adds the tenant scoping a multi-tenant app eventually wants, every locally-created
///    draft silently disappears from the list. A fake value that currently matches nothing is
///    harder to find later than an absent one.
///
/// ## Where the real values come from
///
/// The author is the signed-in user. Unauthenticated, this **refuses** rather than inventing a
/// placeholder: a rapportino is authored by somebody, and a draft attributed to nobody is exactly
/// the shape of the `user-<timestamp>` bug this codebase already fixed once.
///
/// The tenant is read from the local mirror, which sync fills and which is single-tenant by
/// construction — every row on the device belongs to the signed-in user's tenant, so any synced
/// row answers the question. Before the first sync there is genuinely no answer, and the field is
/// left empty rather than filled with a plausible-looking constant. Empty reads as unknown; `local`
/// reads as a tenant that does not exist.
Future<String?> createLocalDraft(
  WidgetRef ref, {
  required String title,
  String locationId = '',
  String? ticketId,
  String? cantiereId,
  String? customerId,
  String? scheduleId,
  String? tenantId,
  String? workAddress,
}) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return null;

  // A caller creating the draft against a known entity already holds that entity's tenant, which
  // is better evidence than any row the mirror happens to return.
  final db = ref.read(appDatabaseProvider);
  final resolvedTenantId = tenantId ?? await resolveDeviceTenantId(db);

  // A real GUID, not a `draft-<timestamp>` string. The backend treats this as the client-supplied
  // report id from the first attachment upload onward — `POST /api/reports/{id:guid}/attachments`
  // route-constrains it, and `SubmitReportRequest.Id` is a `Guid` field. A timestamp-prefixed
  // string never matched that route at all, so every attachment upload 404'd before the request
  // reached any business logic — the report row not existing yet was never the problem.
  final id = _uuid.v4();
  final repo = ref.read(draftReportRepositoryProvider);
  await repo.createDraft(
    DraftReportsCompanion.insert(
      id: id,
      tenantId: resolvedTenantId,
      createdAt: DateTime.now().toUtc(),
      title: title,
      insertedUserId: user.id,
      locationId: locationId,
      ticketId: Value(ticketId),
      cantiereId: Value(cantiereId),
      customerId: Value(customerId),
      scheduleId: Value(scheduleId),
      // Same shape ReportEditorNotifier._buildMetadataJson/._parseMetadataJson round-trip —
      // workAddress has no column of its own (see DraftReports.metadataJson's doc comment).
      metadataJson: Value(
        (workAddress?.isNotEmpty ?? false) ? jsonEncode({'workAddress': workAddress}) : null,
      ),
      isLocalOnly: const Value(true),
      stato: const Value('Bozza'),
    ),
  );

  // Seed the creating technician as the first staff row. Almost every rapportino is worked and
  // filed by the same person — without this, every single draft made the operator manually add
  // themselves to the staff list before they could enter their own hours. The row is otherwise
  // empty (no hours yet); it only names who's on the job.
  await repo.upsertStaff(
    ReportStaffTableCompanion.insert(
      id: _uuid.v4(),
      tenantId: resolvedTenantId,
      createdAt: DateTime.now().toUtc(),
      reportId: id,
      userId: user.id,
    ),
  );

  return id;
}

/// The tenant every synced row on this device belongs to, or `''` before the first sync.
///
/// Tickets first because they are the most likely table to be populated for a technician, then two
/// fallbacks. Returning `''` is a real answer — "this device does not know yet" — and the server
/// assigns the true tenant on submit regardless.
Future<String> resolveDeviceTenantId(AppDatabase db) async {
  final ticket = await (db.select(db.tickets)..limit(1)).getSingleOrNull();
  if (ticket != null) return ticket.tenantId;

  final location = await (db.select(db.locations)..limit(1)).getSingleOrNull();
  if (location != null) return location.tenantId;

  final customer = await (db.select(db.customers)..limit(1)).getSingleOrNull();
  return customer?.tenantId ?? '';
}

// ══════════════════════════════════════════════════════════════════════════════
// Rework — turning a rejected rapportino back into an editable draft.
// ══════════════════════════════════════════════════════════════════════════════

/// Creates a new local draft seeded from a rejected report's own data, so the technician can fix
/// it and resubmit. Returns the new draft's id, or `null` when creation is refused (same reason
/// as [createLocalDraft]: no signed-in author to attribute it to).
///
/// ## Why a new report id, not editing [source] in place
///
/// `ReportStateMachine.CanInvia` (backend) only allows `Bozza → Inviato` — a `Respinto` report
/// cannot be resubmitted under its own id; `POST /api/reports/submit` would reject it with
/// "Il rapportino è già in stato Respinto" before ever reaching the network in a useful way.
/// There is also no rejection-reason field on the backend to carry forward — `POST
/// /api/reports/{id}/respingi` takes no request body and the `Report` entity has no such column
/// (checked: `ReportsController.cs`, `ReportService.RespingiAsync`, `Report.cs`). So "rework"
/// here means starting a genuinely new report — a fresh client-generated id, submitted through
/// the ordinary `Bozza → Inviato` path — seeded with the rejected report's data, rather than
/// reopening the old one. The rejected report itself is left exactly as it was: the record of
/// what happened and when.
///
/// Copies the header fields the mobile editor tracks (title/details/technicianNotes/
/// ticket-cantiere-schedule-customer-location links, materialiNotRequired) plus every
/// staff/materiali/controlli row. Deliberately does NOT copy the signatures or the customer sign-off text — those
/// attest to a specific version of the report the office already rejected, and must be recaptured
/// for the reworked one.
Future<String?> createReworkDraft(WidgetRef ref, DraftReport source) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return null;

  final repo = ref.read(draftReportRepositoryProvider);
  final id = _uuid.v4();
  final now = DateTime.now().toUtc();

  await repo.createDraft(
    DraftReportsCompanion.insert(
      id: id,
      tenantId: source.tenantId,
      createdAt: now,
      title: source.title,
      scheduleId: Value(source.scheduleId),
      ticketId: Value(source.ticketId),
      cantiereId: Value(source.cantiereId),
      customerId: Value(source.customerId),
      details: Value(source.details),
      metadataJson: Value(source.metadataJson),
      insertedUserId: user.id,
      locationId: source.locationId,
      technicianNotes: Value(source.technicianNotes),
      materialiNotRequired: Value(source.materialiNotRequired),
      isLocalOnly: const Value(true),
      stato: const Value('Bozza'),
    ),
  );

  for (final s in await repo.getStaff(source.id)) {
    await repo.upsertStaff(
      ReportStaffTableCompanion.insert(
        id: _uuid.v4(),
        tenantId: source.tenantId,
        createdAt: now,
        reportId: id,
        userId: s.userId,
        hoursWorked: Value(s.hoursWorked),
        kmTraveled: Value(s.kmTraveled),
        vehicle: Value(s.vehicle),
        costPerKm: Value(s.costPerKm),
        notes: Value(s.notes),
        startTime: Value(s.startTime),
        endTime: Value(s.endTime),
        pauseMinutes: Value(s.pauseMinutes),
      ),
    );
  }

  for (final m in await repo.getMateriali(source.id)) {
    await repo.upsertMateriale(
      ReportMaterialiCompanion.insert(
        id: _uuid.v4(),
        tenantId: source.tenantId,
        createdAt: now,
        reportId: id,
        materialeId: Value(m.materialeId),
        freeTextName: Value(m.freeTextName),
        quantity: m.quantity,
        unitOfMeasure: Value(m.unitOfMeasure),
        notes: Value(m.notes),
        magazzinoId: Value(m.magazzinoId),
      ),
    );
  }

  for (final c in await repo.getControlli(source.id)) {
    await repo.upsertControllo(
      ReportControlliCompanion.insert(
        id: _uuid.v4(),
        tenantId: source.tenantId,
        createdAt: now,
        reportId: id,
        controlId: c.controlId,
        stringValue: Value(c.stringValue),
        boolValue: Value(c.boolValue),
        dateValue: Value(c.dateValue),
      ),
    );
  }

  return id;
}

// ══════════════════════════════════════════════════════════════════════════════
// Cantiere-only creation — a real backend Report, hydrated into a local editable draft.
// ══════════════════════════════════════════════════════════════════════════════

/// Creates a rapportino from a cantiere's own logged hours (`POST
/// /api/reports/from-cantiere-worklogs`) and hydrates it into a local draft the ordinary editor
/// (`AppRoutes.rapportiniEditor`) can open, returning the new draft's id. Returns `null` when
/// creation is refused (same reason as [createLocalDraft]: no signed-in author to attribute it to)
/// — the backend call is never even attempted in that case.
///
/// ## Why this reuses the backend-issued report id for the local draft, unlike every other
/// creation path in this file
///
/// [createLocalDraft] and [createReworkDraft] both generate a fresh client-side GUID and the
/// report is genuinely new on the server the first time it hears about it (at submit time). Here
/// the server already created the `Report` row — with real `ReportStaff` rows already populated
/// from the technician's (and, if they batch-started as squadra lead, their whole team's)
/// `CantiereWorkLog` entries — before this function ever runs. Reusing that same id, rather than
/// minting a second one, is what lets `POST /api/reports/submit` find it again later:
/// `ReportSubmitService.SubmitAsync` already treats a `request.Id` that matches an existing Report
/// as an update-in-place (`existingReport ?? new Report {...}`) rather than a duplicate create —
/// the exact same shape it uses for a schedule-started rapportino
/// (`ReportLifecycleService.StartFromScheduleAsync`, `POST /api/schedules/{id}/start`, not yet
/// consumed by mobile). So the local `draft_reports` row created here is keyed by the backend's
/// own id, not a new one — the two are the same report from the very first write.
///
/// ## Hours hydration, and the zero-worklogs fallback
///
/// The create call's response is just `{ id }` — no staff rows in it (see
/// `CantiereReportApiClient.createFromCantiereWorklogs`). A follow-up `GET /api/reports/{id}`
/// reads back what the server actually seeded. If that read fails (e.g. the connection drops
/// between the two calls), the backend Report still exists — degrading to the zero-worklogs
/// fallback below rather than rethrowing avoids stranding it with no local draft pointing at it at
/// all.
///
/// When the fetch comes back empty — the caller had zero unconsumed worklogs for this cantiere,
/// which the backend always allows (see `IReportService.CreateFromCantiereWorkLogsAsync`'s own doc
/// comment) — this seeds the creating technician as a blank first staff row, exactly like
/// [createLocalDraft] does for a brand-new manual rapportino: the editor then behaves exactly like
/// today's manual-entry flow for hours, with no special empty-state of its own.
Future<String?> createCantiereReportDraft(
  WidgetRef ref, {
  required String cantiereId,
  required String cantiereName,
  String? customerId,
  String? tenantId,
  String? workAddress,
}) async {
  final user = ref.read(currentUserProvider);
  if (user == null) return null;

  final api = ref.read(cantiereReportApiClientProvider);
  final reportId = await api.createFromCantiereWorklogs(cantiereId);

  List<ReportStaffSeedDto> staffSeeds;
  try {
    staffSeeds = await api.fetchReportStaff(reportId);
  } catch (_) {
    // Best-effort: see this function's doc comment on why a failure here degrades to the
    // zero-worklogs fallback instead of losing the backend report that already exists.
    staffSeeds = const [];
  }

  final db = ref.read(appDatabaseProvider);
  final resolvedTenantId = tenantId ?? await resolveDeviceTenantId(db);
  final repo = ref.read(draftReportRepositoryProvider);
  final now = DateTime.now().toUtc();

  await repo.createDraft(
    DraftReportsCompanion.insert(
      id: reportId,
      tenantId: resolvedTenantId,
      createdAt: now,
      title: 'Rapportino — $cantiereName',
      insertedUserId: user.id,
      locationId: '',
      cantiereId: Value(cantiereId),
      customerId: Value(customerId),
      metadataJson: Value(
        (workAddress?.isNotEmpty ?? false) ? jsonEncode({'workAddress': workAddress}) : null,
      ),
      isLocalOnly: const Value(true),
      stato: const Value('Bozza'),
    ),
  );

  if (staffSeeds.isEmpty) {
    await repo.upsertStaff(
      ReportStaffTableCompanion.insert(
        id: _uuid.v4(),
        tenantId: resolvedTenantId,
        createdAt: now,
        reportId: reportId,
        userId: user.id,
      ),
    );
  } else {
    for (final s in staffSeeds) {
      await repo.upsertStaff(
        ReportStaffTableCompanion.insert(
          id: _uuid.v4(),
          tenantId: resolvedTenantId,
          createdAt: now,
          reportId: reportId,
          userId: s.userId,
          hoursWorked: Value(s.hoursWorked),
          kmTraveled: Value(s.kmTraveled),
          startTime: Value(s.startTime),
          endTime: Value(s.endTime),
        ),
      );
    }
  }

  return reportId;
}
