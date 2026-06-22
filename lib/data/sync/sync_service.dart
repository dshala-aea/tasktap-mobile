import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';
import '../local/app_database.dart';
import 'sync_dto.dart';

/// Calls GET /api/sync/mobile?since=[lastSync], upserts every entity into
/// Drift, and updates sync_meta.lastSync.
///
/// Design contract:
/// - Idempotent: calling twice produces the same result.
/// - Delta-aware: uses lastSync as the `since` param; null → full sync.
/// - Offline-safe: throws if the network call fails; the caller decides retry.
class SyncService {
  SyncService({required this.db, required this.dio});

  final AppDatabase db;
  final Dio dio;

  static const _path = '/api/sync/mobile';

  /// Perform a delta sync.
  ///
  /// Returns the [DateTime] of the sync snapshot on success.
  /// Throws on network error (caller should surface this to the UI).
  Future<DateTime> sync() async {
    final lastSync = await db.getLastSync();
    final queryParams = <String, String>{};
    if (lastSync != null) {
      queryParams['since'] = lastSync.toUtc().toIso8601String();
    }

    final response = await dio.get<Map<String, dynamic>>(
      _path,
      queryParameters: queryParams,
    );

    final payload =
        SyncResultDto.fromJson(response.data as Map<String, dynamic>);

    await db.transaction(() async {
      await _upsertCustomers(payload.customers);
      await _upsertLocations(payload.locations);
      await _upsertTickets(payload.tickets);
      await _upsertSchedules(payload.schedules);
      await _upsertDraftReports(payload.draftReports);
      await _upsertTicketStatuses(payload.ticketStatuses);
      await _upsertTicketTypes(payload.ticketTypes);
    });

    await db.setLastSync(payload.syncedAt);
    return payload.syncedAt;
  }

  // ── Upsert helpers ─────────────────────────────────────────────────────────

  Future<void> _upsertCustomers(List<CustomerDto> list) async {
    for (final c in list) {
      await db.into(db.customers).insertOnConflictUpdate(
            CustomersCompanion.insert(
              id: c.id,
              tenantId: c.tenantId,
              createdAt: c.createdAt,
              updatedAt: Value(c.updatedAt),
              companyName: c.companyName,
              taxId: Value(c.taxId),
              address: Value(c.address),
              city: Value(c.city),
              postalCode: Value(c.postalCode),
              country: Value(c.country),
              phone: Value(c.phone),
              email: Value(c.email),
              contactPerson: Value(c.contactPerson),
              notes: Value(c.notes),
              isActive: Value(c.isActive),
            ),
          );
    }
  }

  Future<void> _upsertLocations(List<LocationDto> list) async {
    for (final l in list) {
      await db.into(db.locations).insertOnConflictUpdate(
            LocationsCompanion.insert(
              id: l.id,
              tenantId: l.tenantId,
              createdAt: l.createdAt,
              updatedAt: Value(l.updatedAt),
              customerId: l.customerId,
              name: l.name,
              address: Value(l.address),
              city: Value(l.city),
              postalCode: Value(l.postalCode),
              country: Value(l.country),
              latitude: Value(l.latitude),
              longitude: Value(l.longitude),
              phone: Value(l.phone),
              notes: Value(l.notes),
              isActive: Value(l.isActive),
            ),
          );
    }
  }

  Future<void> _upsertTickets(List<TicketDto> list) async {
    for (final t in list) {
      await db.into(db.tickets).insertOnConflictUpdate(
            TicketsCompanion.insert(
              id: t.id,
              tenantId: t.tenantId,
              createdAt: t.createdAt,
              updatedAt: Value(t.updatedAt),
              title: t.title,
              description: Value(t.description),
              customerId: t.customerId,
              locationId: t.locationId,
              assignedUserId: Value(t.assignedUserId),
              statusId: t.statusId,
              typeId: t.typeId,
              agentId: Value(t.agentId),
              closedAt: Value(t.closedAt),
              technicianNotes: Value(t.technicianNotes),
              internalNotes: Value(t.internalNotes),
              contractId: Value(t.contractId),
              prodottoAssistenzaId: Value(t.prodottoAssistenzaId),
              commessaId: Value(t.commessaId),
            ),
          );
    }
  }

  Future<void> _upsertSchedules(List<ScheduleDto> list) async {
    for (final s in list) {
      await db.into(db.schedules).insertOnConflictUpdate(
            SchedulesCompanion.insert(
              id: s.id,
              tenantId: s.tenantId,
              createdAt: s.createdAt,
              updatedAt: Value(s.updatedAt),
              ticketId: Value(s.ticketId),
              activityDate: s.activityDate,
              timeStartMinutes:
                  ScheduleDto.parseTimeToMinutes(s.timeStart),
              timeEndMinutes: ScheduleDto.parseTimeToMinutes(s.timeEnd),
              userId: s.userId,
              statusId: s.statusId,
              locationId: s.locationId,
              allDay: Value(s.allDay),
              title: s.title,
              description: s.description,
              teamLeadId: Value(s.teamLeadId),
              staffIds: Value(s.staffIds),
              squadraId: Value(s.squadraId),
            ),
          );
    }
  }

  Future<void> _upsertDraftReports(List<ReportDto> list) async {
    for (final r in list) {
      await db.into(db.draftReports).insertOnConflictUpdate(
            DraftReportsCompanion.insert(
              id: r.id,
              tenantId: r.tenantId,
              createdAt: r.createdAt,
              updatedAt: Value(r.updatedAt),
              title: r.title,
              scheduleId: Value(r.scheduleId),
              ticketId: Value(r.ticketId),
              customerId: Value(r.customerId),
              details: Value(r.details),
              insertedUserId: r.insertedUserId,
              locationId: r.locationId,
              startedAt: Value(r.startedAt),
              endedAt: Value(r.endedAt),
              documentTemplateId: Value(r.documentTemplateId),
              customerSignatureAllegatoId:
                  Value(r.customerSignatureAllegatoId),
              technicianSignatureAllegatoId:
                  Value(r.technicianSignatureAllegatoId),
              technicianNotes: Value(r.technicianNotes),
              closedAt: Value(r.closedAt),
              stato: Value(r.stato),
              inviatoAt: Value(r.inviatoAt),
              controllatoAt: Value(r.controllatoAt),
              controllatoDa: Value(r.controllatoDa),
              fatturatoAt: Value(r.fatturatoAt),
              materialiNotRequired: Value(r.materialiNotRequired),
              customerSignoffText: Value(r.customerSignoffText),
              customerSignoffAt: Value(r.customerSignoffAt),
              // Synced-down reports are never local-only
              isLocalOnly: const Value(false),
            ),
          );
    }
  }

  Future<void> _upsertTicketStatuses(List<TicketStatusDto> list) async {
    for (final s in list) {
      await db.into(db.ticketStatuses).insertOnConflictUpdate(
            TicketStatusesCompanion.insert(
              id: Value(s.id),
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
              id: Value(t.id),
              tenantId: t.tenantId,
              name: t.name,
              description: Value(t.description),
            ),
          );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Riverpod provider
// ══════════════════════════════════════════════════════════════════════════════

/// Provides the [AppDatabase] singleton.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Provides the [SyncService].
final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    db: ref.watch(appDatabaseProvider),
    dio: ref.watch(dioProvider),
  );
});

/// Notifier that manages sync state (idle / syncing / error / done).
enum SyncStatus { idle, syncing, done, error }

class SyncState {
  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSync,
    this.errorMessage,
  });

  final SyncStatus status;
  final DateTime? lastSync;
  final String? errorMessage;

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSync,
    String? errorMessage,
  }) =>
      SyncState(
        status: status ?? this.status,
        lastSync: lastSync ?? this.lastSync,
        errorMessage: errorMessage,
      );
}

class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier(this._service, this._db) : super(const SyncState()) {
    _loadLastSync();
  }

  final SyncService _service;
  final AppDatabase _db;

  Future<void> _loadLastSync() async {
    final last = await _db.getLastSync();
    if (last != null) {
      state = state.copyWith(lastSync: last);
    }
  }

  Future<void> performSync() async {
    if (state.status == SyncStatus.syncing) return;
    state = state.copyWith(status: SyncStatus.syncing);
    try {
      final ts = await _service.sync();
      state = SyncState(status: SyncStatus.done, lastSync: ts);
    } catch (e) {
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}

final syncProvider =
    StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(
    ref.watch(syncServiceProvider),
    ref.watch(appDatabaseProvider),
  );
});
