// dart format width=100
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/reports/draft_report_repository.dart';
import '../../domain/reports/strumenti_selection.dart';
import 'report_editor_providers.dart' show draftReportRepositoryProvider;

// ══════════════════════════════════════════════════════════════════════════════
// Strumenti selection of one rapportino
//
// Source of truth is the local mirror, so this works offline:
//  - `strumenti` (the active tenant catalogue, delivered by sync) feeds the picker and the kit
//    pre-fill (`isMine`);
//  - `report_strumenti` rows with isLocal = true are the selection authored on this device, the
//    only rows the submit body is built from.
//
// Pre-fill happens ONCE per draft, guarded by `draft_reports.strumentiPrefilled`:
//   1. a draft the server already holds instruments for (imported Bozza) adopts that selection:
//      the server's selection wins over the kit;
//   2. otherwise the technician's own kit (`isMine`) is selected.
// A technician who then deselects everything is never re-filled. The flag is not set while the
// catalogue is still empty (sync has not delivered it, or the user lacks `team.strumento.read`),
// so the pre-fill still happens the first time the catalogue exists.
// ══════════════════════════════════════════════════════════════════════════════

/// One selected instrument, display data already resolved (catalogue wins over the snapshot the
/// row was saved with, so a recalibration shows its new expiry).
class StrumentoSelectionItem {
  const StrumentoSelectionItem({
    required this.strumentoId,
    required this.name,
    required this.matricola,
    required this.calibrationExpiry,
    required this.expiredAcknowledged,
    required this.expired,
    required this.inCatalogue,
  });

  final String strumentoId;
  final String name;
  final String matricola;

  /// Civil date 'yyyy-MM-dd', or null (no calibration expiry recorded).
  final String? calibrationExpiry;
  final bool expiredAcknowledged;

  /// Local hint for the report's work date; the server recomputes and wins.
  final bool expired;

  /// False when the instrument was retired from the catalogue after it was saved on the draft.
  final bool inCatalogue;
}

class StrumentiSelectionState {
  const StrumentiSelectionState({
    this.isLoading = true,
    this.items = const [],
    this.available = const [],
    this.workDate = '',
  });

  final bool isLoading;
  final List<StrumentoSelectionItem> items;

  /// Catalogue instruments not yet selected, the technician's own first.
  final List<StrumentoRow> available;
  final String workDate;

  /// Expired instruments the technician has not acknowledged yet: the submit would be a 422.
  int get unacknowledgedExpired => items.where((i) => i.expired && !i.expiredAcknowledged).length;
}

class StrumentiSelectionNotifier extends StateNotifier<StrumentiSelectionState> {
  StrumentiSelectionNotifier({required DraftReportRepository repo, required this.reportId})
    : _repo = repo,
      super(const StrumentiSelectionState()) {
    ready = _hydrate();
  }

  final DraftReportRepository _repo;
  final String reportId;

  /// Resolves once the initial load (and the one-time pre-fill) finished or gave up.
  late final Future<void> ready;

  static String rowId(String reportId, String strumentoId) => 'str-$reportId-$strumentoId';

  Future<void> _hydrate() async {
    try {
      final draft = await _repo.getDraft(reportId);
      if (draft == null) {
        if (mounted) state = const StrumentiSelectionState(isLoading: false);
        return;
      }
      final catalogue = await _repo.getStrumentiCatalogue();
      final local = await _repo.getLocalStrumenti(reportId);

      if (local.isEmpty && !draft.strumentiPrefilled) {
        final server = (await _repo.getServerStrumenti(reportId))
            .where((s) => s.strumentoId != null)
            .toList();
        if (server.isNotEmpty) {
          await _repo.seedLocalStrumenti(
            reportId,
            [
              for (final s in server)
                ReportStrumentiCompanion.insert(
                  id: rowId(reportId, s.strumentoId!),
                  reportId: reportId,
                  strumentoId: Value(s.strumentoId),
                  name: s.name,
                  matricola: s.matricola,
                  calibrationExpiry: Value(s.calibrationExpiry),
                  certificateReference: Value(s.certificateReference),
                  expiredAcknowledged: Value(s.expiredAcknowledged),
                  isLocal: const Value(true),
                ),
            ],
            markPrefilled: true,
          );
        } else {
          final kit = catalogue.where((s) => s.isMine).toList();
          await _repo.seedLocalStrumenti(
            reportId,
            [for (final s in kit) _companionFor(s)],
            // An empty catalogue means "not delivered yet", not "the technician owns nothing".
            markPrefilled: catalogue.isNotEmpty,
          );
        }
      }
      await _reload(draft: draft);
    } catch (_) {
      // Best-effort, like the editor's own hydration: never crash the sheet over a local read.
      if (mounted && state.isLoading) state = const StrumentiSelectionState(isLoading: false);
    }
  }

  ReportStrumentiCompanion _companionFor(StrumentoRow s, {bool acknowledged = false}) {
    return ReportStrumentiCompanion.insert(
      id: rowId(reportId, s.id),
      reportId: reportId,
      strumentoId: Value(s.id),
      name: s.name,
      matricola: s.matricola,
      calibrationExpiry: Value(s.calibrationExpiry),
      certificateReference: Value(s.certificateReference),
      expiredAcknowledged: Value(acknowledged),
      isLocal: const Value(true),
    );
  }

  Future<void> _reload({DraftReport? draft}) async {
    final d = draft ?? await _repo.getDraft(reportId);
    if (d == null || !mounted) return;
    final catalogue = await _repo.getStrumentiCatalogue();
    final local = await _repo.getLocalStrumenti(reportId);
    if (!mounted) return;
    final byId = {for (final c in catalogue) c.id: c};
    final workDate = workDateLabel(d.startedAt, d.createdAt);
    final items = <StrumentoSelectionItem>[];
    for (final r in local) {
      final id = r.strumentoId;
      if (id == null) continue;
      final cat = byId[id];
      final expiry = cat != null ? cat.calibrationExpiry : r.calibrationExpiry;
      final expired = isStrumentoExpiredOn(expiry, workDate);
      items.add(
        StrumentoSelectionItem(
          strumentoId: id,
          name: cat?.name ?? r.name,
          matricola: cat?.matricola ?? r.matricola,
          calibrationExpiry: expiry,
          // A valid instrument never carries an acknowledgement (the server rejects it).
          expiredAcknowledged: expired && r.expiredAcknowledged,
          expired: expired,
          inCatalogue: cat != null,
        ),
      );
    }
    final selected = items.map((i) => i.strumentoId).toSet();
    final available = catalogue.where((c) => !selected.contains(c.id)).toList()
      ..sort((a, b) {
        if (a.isMine != b.isMine) return a.isMine ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    state = StrumentiSelectionState(
      isLoading: false,
      items: items,
      available: available,
      workDate: workDate,
    );
  }

  Future<void> add(String strumentoId) async {
    if (state.items.any((i) => i.strumentoId == strumentoId)) return;
    final cat = (await _repo.getStrumentiCatalogue()).where((s) => s.id == strumentoId);
    if (cat.isEmpty) return;
    await _repo.upsertLocalStrumento(_companionFor(cat.first));
    await _reload();
  }

  Future<void> remove(String strumentoId) async {
    await _repo.deleteLocalStrumento(reportId, strumentoId);
    await _reload();
  }

  /// Only meaningful for an expired instrument; a valid one is ignored (the flag would be a 422).
  Future<void> setAcknowledged(String strumentoId, bool value) async {
    final item = state.items.where((i) => i.strumentoId == strumentoId);
    if (item.isEmpty || !item.first.expired) return;
    await _repo.upsertLocalStrumento(
      ReportStrumentiCompanion(
        id: Value(rowId(reportId, strumentoId)),
        reportId: Value(reportId),
        strumentoId: Value(strumentoId),
        name: Value(item.first.name),
        matricola: Value(item.first.matricola),
        calibrationExpiry: Value(item.first.calibrationExpiry),
        expiredAcknowledged: Value(value),
        isLocal: const Value(true),
      ),
    );
    await _reload();
  }
}

final strumentiSelectionProvider = StateNotifierProvider.autoDispose
    .family<StrumentiSelectionNotifier, StrumentiSelectionState, String>((ref, reportId) {
      return StrumentiSelectionNotifier(
        repo: ref.watch(draftReportRepositoryProvider),
        reportId: reportId,
      );
    });
