// dart format width=100
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/ai/ai_api_client.dart';
import '../../data/local/app_database.dart';
import '../../data/reports/import_server_report.dart' show controlRowId;
import '../../presentation/providers/report_editor_providers.dart'
    show draftReportRepositoryProvider;
import 'create_draft.dart';

const _uuid = Uuid();

/// Applies a confirmed AI draft to the phone's own rapportino.
///
/// This is the mobile half of spec §5.5: the server resolves the draft against real tenant data
/// and persists nothing (§5.4), so the write belongs here, into the same Drift draft the wizard
/// fills by hand. Everything after this — review, signatures, the queue, the submit — is the path
/// that already exists, unchanged. The only network call this rapportino will ever make is the
/// submit, and it is atomic and idempotent by key.
///
/// Models `createReworkDraft`: a header, then one loop per child table. No new abstraction, because
/// the two functions that already do this (`createLocalDraft`, `createReworkDraft`) established the
/// companions, the ordering and the refusal semantics.
///
/// Returns the new local report id, or null when the device cannot attribute a draft to anybody
/// (no signed-in internal user id) — the same refusal `createLocalDraft` makes, for the same reason.
///
/// What the response does NOT carry and this function therefore does not write: any signature, and
/// any location fallback. A null `locationId` is written as an empty string, which reads as
/// "unknown" and is what the editor's own validation rejects at submit time
/// (`DraftValidationIssue.missingLocation`).
///
/// The one thing the response does not carry that this function DOES write is provenance —
/// `isAiAssisted`, in the final `saveDraft` below, in the same companion as the data. It must not be
/// left to `ReportEditorNotifier.markAiAssisted()`: that setter autosaves the whole header from
/// `state`, and a just-constructed `reportEditorProvider` still holds the blank placeholder while
/// `_hydrate()` resolves, so calling it here would overwrite everything this function just wrote.
/// ADR-0016 §2 makes the flag coarse provenance, set where generated text enters the draft — which
/// is here, so the value is `true` and not a caller's choice.
Future<String?> applyConfirmedDraft(
  WidgetRef ref, {
  required AiConversationConfirmResponse response,
  String? ticketId,
  String? cantiereId,
}) async {
  final id = await createLocalDraft(
    ref,
    title: response.title,
    locationId: response.locationId ?? '',
    ticketId: response.ticketId ?? ticketId,
    cantiereId: response.cantiereId ?? cantiereId,
  );
  if (id == null) return null;

  final repo = ref.read(draftReportRepositoryProvider);
  final draft = await repo.getDraft(id);
  if (draft == null) return null;
  final tenantId = draft.tenantId;
  final now = DateTime.now().toUtc();

  for (final s in response.staff) {
    await repo.upsertStaff(
      ReportStaffTableCompanion.insert(
        id: _uuid.v4(),
        tenantId: tenantId,
        createdAt: now,
        reportId: id,
        userId: s.userId,
        hoursWorked: Value(s.hoursWorked),
        kmTraveled: Value(s.kmTraveled),
        vehicle: Value(s.vehicle),
      ),
    );
  }

  for (final m in response.materials) {
    // The free-text path's "Da verificare" marker rides in `notes` and is shown on the row:
    // the technician has to see that a line was dictated rather than looked up.
    await repo.upsertMateriale(
      ReportMaterialiCompanion.insert(
        id: _uuid.v4(),
        tenantId: tenantId,
        createdAt: now,
        reportId: id,
        materialeId: Value(m.materialeId),
        freeTextName: Value(m.freeTextName),
        quantity: m.quantity,
        unitOfMeasure: Value(m.unitOfMeasure),
        notes: Value(m.notes),
        // magazzinoId intentionally absent: nothing resolved a warehouse, and a magazzino is what
        // turns a material line into a stock scarico. Guessing one would move stock nobody asked for.
      ),
    );
  }

  if (response.controlli.isNotEmpty) {
    await repo.upsertControlli([
      for (final c in response.controlli)
        ReportControlliCompanion.insert(
          // The Controlli step's own row id, so its next edit UPDATES this row instead of
          // inserting a second answer for the same TicketControl.
          id: controlRowId(id, c.ticketControlId),
          tenantId: tenantId,
          createdAt: now,
          reportId: id,
          controlId: c.ticketControlId,
          stringValue: Value(c.stringValue),
          boolValue: Value(c.boolValue),
          dateValue: Value(c.dateValue),
          numberValue: Value(c.numberValue),
          note: Value(c.note),
        ),
    ]);
  }

  // materialiNotRequired and customerSignoffText are header fields the confirm response corrects
  // for us; carry them or the editor shows a report that contradicts what the server resolved.
  //
  // isAiAssisted rides here rather than through ReportEditorNotifier.markAiAssisted(): that setter
  // autosaves the entire header from `state`, and a provider constructed this instant still holds
  // the blank placeholder until its async _hydrate() resolves, so it would write blanks over
  // everything above. Same companion as the data, no notifier, no race.
  //
  // tenantId/createdAt/title/insertedUserId/locationId are carried from the row just written even
  // though this companion does not change them: `saveDraft` is an `insertOnConflictUpdate`, and
  // drift checks a companion's integrity against the table's NOT NULL columns rather than against
  // the branch that ends up running, so a partial companion throws
  // "This value was required, but isn't present" instead of updating. Values are read from `draft`
  // (not re-derived) so the update writes back exactly what `createLocalDraft` stored.
  await repo.saveDraft(
    DraftReportsCompanion(
      id: Value(id),
      tenantId: Value(tenantId),
      createdAt: Value(draft.createdAt),
      title: Value(draft.title),
      insertedUserId: Value(draft.insertedUserId),
      locationId: Value(draft.locationId),
      materialiNotRequired: Value(response.materialiNotRequired),
      customerSignoffText: Value(response.customerSignoffText),
      details: Value(response.details),
      isAiAssisted: const Value(true),
      updatedAt: Value(now),
    ),
  );

  return id;
}
