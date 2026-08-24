// dart format width=100
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/ticket/ticket_detail_api_client.dart';
import '../../features/ticket/ticket_providers.dart' show ticketControlsProvider;
import '../local/app_database.dart';
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
    // TicketControlDto.fromJson maps this int back through `_controlTypeFromInt`, whose ordering
    // matches ControlType's declaration order — round-tripping `.index` is safe as long as that
    // stays true, same as every other backend-mirrored enum in this app.
    'type': c.type.index,
    'isRequired': c.isRequired,
    'options': c.options,
    'valoreLimite': c.valoreLimite,
    'sortOrder': c.sortOrder,
    'status': c.status,
    'stringValue': c.stringValue,
    'boolValue': c.boolValue,
    'dateValue': c.dateValue?.toIso8601String(),
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
      try {
        final groups = await ref.watch(ticketControlsProvider(ticketId).future);
        // Fire-and-forget from the caller's perspective, but awaited here so a test (or a
        // technician going offline moments later) can rely on the cache already being written
        // by the time this provider resolves.
        await cacheRepo.cacheControls(ticketId, groups);
        return groups;
      } catch (_) {
        final cached = await cacheRepo.getCachedControls(ticketId);
        if (cached != null) return cached;
        rethrow;
      }
    });
