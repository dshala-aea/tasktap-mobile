// dart format width=100
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ticket/ticket_controls_mirror.dart' show ticketControlGroupsFromMirror;
import '../../features/ticket/ticket_detail_api_client.dart';
import '../../features/ticket/ticket_providers.dart' show ticketControlsProvider;
import '../local/app_database.dart';
import '../local/checklist_read_repository.dart';
import '../sync/connectivity_provider.dart' show isOnlineProvider;
import '../sync/sync_service.dart' show appDatabaseProvider;

// ══════════════════════════════════════════════════════════════════════════════
// TicketControlsCacheRepository
//
// Every other section of the offline-first rapportino form (materials, staff, photos,
// signatures, GPS) works with zero network at capture time. The Controlli checklist
// (GET /api/tickets/{ticketId}/controls, `ticketControlsProvider` in
// features/ticket/ticket_providers.dart) was the one exception: with no local cache, going
// offline mid-draft meant `TicketDetailOfflineException` and nothing to answer.
//
// This repository persists the checklist tree the first time it is fetched online, following
// the same "cache on success, upsert one row" shape as DraftReportRepository. It does not touch
// `ticket_providers.dart`/`ticket_detail_api_client.dart` (out of scope for this change; those
// files stay online-only, exactly as they already are for the ticket-detail Controllo tab) — it
// wraps the existing provider from the rapportino feature instead. See
// `cachedTicketControlsProvider` below for the wrapping.
//
// The cache is the *second* offline source, not the first: the sync mirror is read whenever it can
// answer for the ticket (see `getMirroredControlsIfAuthoritative`), because a report is drafted
// mostly on site, and a ticket that synced has its checklist on the device whether or not this
// technician ever opened that ticket's controls online before. The cache covers exactly the gap
// the mirror cannot: a ticket whose checklist the payload omitted, or one never synced at all.
//
// `TicketControlGroupDto`/`TicketControlDto` only ever came from the server before this, so
// neither has a `toJson` — the (de)serialization here is this repository's own, round-tripping
// exactly the fields `TicketControlGroupDto.fromJson`/`TicketControlDto.fromJson` read.
// ══════════════════════════════════════════════════════════════════════════════

class TicketControlsCacheRepository {
  TicketControlsCacheRepository(this._db);

  final AppDatabase _db;

  /// Persists (overwrites) the cached checklist for [ticketId].
  Future<void> cacheControls(String ticketId, List<TicketControlGroupDto> groups) async {
    final json = jsonEncode(groups.map(_groupToJson).toList());
    await _db
        .into(_db.cachedTicketControls)
        .insertOnConflictUpdate(
          CachedTicketControlsCompanion.insert(
            ticketId: ticketId,
            controlsJson: json,
            cachedAt: DateTime.now().toUtc(),
          ),
        );
  }

  /// The last cached checklist for [ticketId], or `null` when nothing has ever been cached
  /// (never fetched online yet on this device).
  Future<List<TicketControlGroupDto>?> getCachedControls(String ticketId) async {
    final row = await (_db.select(
      _db.cachedTicketControls,
    )..where((t) => t.ticketId.equals(ticketId))).getSingleOrNull();
    if (row == null) return null;

    final decoded = jsonDecode(row.controlsJson);
    if (decoded is! List) return null;
    return decoded.cast<Map<String, dynamic>>().map(TicketControlGroupDto.fromJson).toList();
  }

  /// The checklist as the **sync mirror** holds it for [ticketId], when the mirror can actually
  /// answer for that ticket — `null` means "cannot tell", never "no controls".
  ///
  /// The mirror is authoritative once the ticket itself has synced and its checklist was not left
  /// out of the payload (`ticket_controls` is replaced wholesale per ticket, so its rows are the
  /// server's list — an empty one is a real "this ticket has no controls"). Until then — a ticket
  /// this device has never seen synced, or one recorded in `checklist_omitted_tickets` while the
  /// batched re-request is still pending — reading it would report a missing answer as a definite
  /// one, so this returns `null` and the caller falls back.
  ///
  /// Preferred over [getCachedControls] wherever it applies: both describe the same server list,
  /// but the mirror is refreshed by every sync and also keeps the observations a local draft
  /// already recorded, while the cache is frozen at the last online fetch this device made.
  Future<List<TicketControlGroupDto>?> getMirroredControlsIfAuthoritative(String ticketId) async {
    final read = ChecklistReadRepository(_db);
    if (!await read.hasSyncedTicket(ticketId)) return null;
    if (await read.isChecklistOmitted(ticketId)) return null;
    return ticketControlGroupsFromMirror(
      controls: await read.getTicketControlRows(ticketId),
      groups: await read.getControlGroups(),
    );
  }

  // ── Serialization ─────────────────────────────────────────────────────────

  static Map<String, dynamic> _groupToJson(TicketControlGroupDto g) => {
    'id': g.id,
    'name': g.name,
    'description': g.description,
    'sortOrder': g.sortOrder,
    'subgroups': g.subgroups.map(_groupToJson).toList(),
    'controls': g.controls.map(_controlToJson).toList(),
  };

  static Map<String, dynamic> _controlToJson(TicketControlDto c) => {
    'id': c.id,
    'templateControlId': c.templateControlId,
    'label': c.label,
    'description': c.description,
    // TicketControlDto.fromJson maps this back through `_controlTypeFromWire`, which matches the
    // backend's own wire names (JsonStringEnumConverter) — write the same names here, not the
    // enum's `.index`, or a cached-then-reloaded control always comes back `unknown`.
    'type': _controlTypeToWire(c.type),
    'isRequired': c.isRequired,
    'options': c.options,
    'valoreLimite': c.valoreLimite,
    'sortOrder': c.sortOrder,
    'status': c.status,
    'stringValue': c.stringValue,
    'boolValue': c.boolValue,
    'dateValue': c.dateValue?.toIso8601String(),
    'numberValue': c.numberValue,
    // A cached-then-reloaded control must keep these too: `controlLineageId` is its
    // version-independent identity (bulk selector), `note` the remark, `prodottoAssistenzaId` the
    // asset it belongs to (null = ticket-level).
    'controlLineageId': c.controlLineageId,
    'note': c.note,
    'prodottoAssistenzaId': c.prodottoAssistenzaId,
  };

  static String _controlTypeToWire(ControlType type) => switch (type) {
    ControlType.text => 'Text',
    ControlType.number => 'Number',
    ControlType.dateTime => 'DateTime',
    ControlType.checkbox => 'Checkbox',
    ControlType.trueFalse => 'TrueFalse',
    ControlType.options => 'Options',
    ControlType.unknown => 'Unknown',
  };
}

final ticketControlsCacheRepositoryProvider = Provider<TicketControlsCacheRepository>((ref) {
  return TicketControlsCacheRepository(ref.watch(appDatabaseProvider));
});

// ══════════════════════════════════════════════════════════════════════════════
// cachedTicketControlsProvider — the offline-aware read the rapportino Controlli step uses.
//
// Wraps `ticketControlsProvider` (unmodified, still online-only, still shared with the
// ticket-detail Controllo tab) rather than replacing it: on a successful online fetch the result
// is cached and returned as-is; on any failure (offline, server error) it falls back to the last
// cached checklist for this ticket, if one exists, and only rethrows when there is nothing cached
// yet — the same "never fetched, nothing to show" case `ticketControlsProvider` already surfaces.
// ══════════════════════════════════════════════════════════════════════════════

final cachedTicketControlsProvider = FutureProvider.autoDispose
    .family<List<TicketControlGroupDto>, String>((ref, ticketId) async {
      final cacheRepo = ref.watch(ticketControlsCacheRepositoryProvider);
      // Two offline-capable sources, tried in order, never merged:
      //  1. the sync mirror, but only when it can answer for this ticket — a ticket the device
      //     knows and whose checklist was not omitted. Its rows are the server's list, refreshed by
      //     every sync, so an empty result there is the real "no controls";
      //  2. the checklist a previous online fetch cached, for the ticket this device has not synced
      //     yet or whose checklist the payload left out. That cache cannot distinguish "none" from
      //     "not fetched", so it is only trusted as a fallback, never as a claim of emptiness.
      // Neither applies: the honest offline state.
      Future<List<TicketControlGroupDto>?> bestKnown() async =>
          await cacheRepo.getMirroredControlsIfAuthoritative(ticketId) ??
          await cacheRepo.getCachedControls(ticketId);

      // Offline, `ticketControlsProvider` answers from the sync mirror — which cannot tell "this
      // ticket has no controls" from "its rows have not synced yet" (it reports the ambiguity as
      // the offline state rather than as an empty checklist). The rapportino must not report either
      // on that ambiguity, so offline it keeps its own rule: the checklist a previous online fetch
      // cached, or the honest offline state.
      if (!ref.watch(isOnlineProvider)) {
        final known = await bestKnown();
        if (known != null) return known;
        throw const TicketDetailOfflineException();
      }
      try {
        final groups = await ref.watch(ticketControlsProvider(ticketId).future);
        // Fire-and-forget from the caller's perspective, but awaited here so a test (or a
        // technician going offline moments later) can rely on the cache already being written
        // by the time this provider resolves.
        await cacheRepo.cacheControls(ticketId, groups);
        return groups;
      } catch (_) {
        final known = await bestKnown();
        if (known != null) return known;
        rethrow;
      }
    });
