// dart format width=100
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/local/app_database.dart';
import '../../data/reports/import_server_report.dart';
import 'import_server_report_action.dart';
import 'rapportino_list_providers.dart' show rapportinoOpensEditor;

/// The rapportino drafts a technician can already work on for one ticket.
///
/// Nothing stopped a ticket from accumulating drafts: "Crea rapportino" minted a fresh local row
/// every time it was pressed, and there is no unique key on `draft_reports(ticket_id, stato)`.
/// Pressing it twice — or once a day for a week, on a ticket touched repeatedly — left several
/// Bozze that each looked like "the" report for that ticket, with no way to tell which one the
/// office would eventually receive.
///
/// The check is deliberately offline-first: local drafts and server-authored Bozze arrive in the
/// same `draft_reports` table, so one Drift read answers for both. A server Bozza created on
/// another device after this phone's last sync cannot be seen here — that is the honest limit of
/// an offline-first warning, and still better than no warning at all.
Future<List<DraftReport>> editableDraftsForTicket(AppDatabase db, String ticketId) async {
  final rows =
      await (db.select(db.draftReports)
            ..where((d) => d.ticketId.equals(ticketId) & d.stato.equals('Bozza'))
            ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]))
          .get();
  // `rapportinoOpensEditor` also excludes a Bozza this device already submitted but whose `stato`
  // has not been flipped by the next sync yet — that row is not something to reopen.
  return rows.where(rapportinoOpensEditor).toList();
}

/// What the technician chose when told a draft already exists for the ticket.
enum ExistingDraftChoice { openExisting, createNew, cancelled }

/// Asks what to do about [drafts], naming the existing draft rather than a bare count.
///
/// Returns [ExistingDraftChoice.cancelled] for a dismissed dialog, so the caller creates nothing
/// by accident — "a second draft appeared anyway" is the one outcome that must never be silent.
Future<ExistingDraftChoice> askAboutExistingDraft(
  BuildContext context, {
  required List<DraftReport> drafts,
}) async {
  final first = drafts.first;
  final choice = await showDialog<ExistingDraftChoice>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bozza già presente',
              style: TextStyle(
                fontFamily: 'Archivo Narrow',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ctx.colors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              drafts.length == 1
                  ? 'Per questo ticket c’è già un rapportino in bozza: «${first.title}». '
                        'Vuoi aprirlo invece di crearne un altro?'
                  : 'Per questo ticket ci sono già ${drafts.length} rapportini in bozza. '
                        'Vuoi aprire «${first.title}», l’ultimo modificato?',
              style: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: ctx.colors.inkMuted),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    label: 'Crea nuova',
                    onPressed: () => Navigator.of(ctx).pop(ExistingDraftChoice.createNew),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Apri bozza',
                    onPressed: () => Navigator.of(ctx).pop(ExistingDraftChoice.openExisting),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return choice ?? ExistingDraftChoice.cancelled;
}

/// Opens an existing editable Bozza in the editor.
///
/// A server-authored Bozza reached this phone as a sync header with no children; opening it as is
/// would show a blank form whose submit deletes the office's data. It is imported first — from the
/// server when online, from the local mirror otherwise. When neither works the editor stays shut
/// and the technician is told why, exactly as the Rapportini list does for the same row.
Future<void> openEditableDraft(BuildContext context, WidgetRef ref, DraftReport draft) async {
  if (!draft.isLocalOnly) {
    try {
      await importServerReportForEditing(ref, reportId: draft.id);
    } on ServerReportNotEditableException {
      if (!context.mounted) return;
      showAppToast(
        context,
        message: 'Questo rapportino non è più modificabile.',
        tone: ToastTone.warning,
      );
      return;
    } catch (_) {
      if (!context.mounted) return;
      showAppToast(
        context,
        message:
            'Per aprire questo rapportino serve la connessione: i dati completi vanno scaricati '
            'sul telefono. Riprova più tardi.',
        tone: ToastTone.error,
      );
      return;
    }
  }
  if (!context.mounted) return;
  context.push(AppRoutes.rapportiniEditor(draft.id));
}
