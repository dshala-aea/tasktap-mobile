// dart format width=100
// lib/features/cantiere/cantiere_providers.dart
//
// Providers backing the technician-facing Cantieri tab (CantieriListScreen,
// CantiereDetailScreen). Both read the local Drift mirror only — no independent network call,
// same offline-first shape as cantieriProvider (features/timbra/cantiere_timbra_screen.dart),
// which this file's cantiereByIdProvider complements with a single-row lookup by id.

import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location/geocoding_service.dart';
import '../../core/time/business_time_providers.dart' show businessTimeProvider;
import '../../core/utils/error_message.dart' show isTransportOrServerFault;
import '../../data/local/app_database.dart';
import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../data/timbratura/cantiere_timbra_sync_service.dart'
    show cantiereSessionRepositoryProvider;
import '../../data/timbratura/cantiere_worklog_api_client.dart';
import '../../presentation/providers/auth_providers.dart' show internalUserIdProvider;

/// A single cantiere by id, or null if none is synced locally with that id. Not filtered by
/// status (unlike `cantieriProvider`) — a cantiere reached via a ticket's link may be
/// Completed/Cancelled, and that's a legitimate state to display, not an error.
///
/// `StreamProvider.autoDispose`, matching every other by-id local-lookup provider in this app
/// (e.g. `customerByIdProvider` in `schedule_providers.dart`) — not a one-shot `FutureProvider`.
/// A plain `FutureProvider` without `autoDispose` would cache its result for the process
/// lifetime: a technician opening a ticket whose cantiere isn't synced yet would get a
/// permanently-cached `null`, never updated even after a later sync brings that cantiere in, and
/// the family cache would grow one never-released entry per cantiere id ever visited.
final cantiereByIdProvider = StreamProvider.autoDispose.family<CantieriData?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.cantieri)..where((c) => c.id.equals(id))).watchSingleOrNull();
});

/// This cantiere's mirrored punches of the signed-in technician, newest first — the cantiere
/// detail's *Timbrature* section.
///
/// Reads `cantiere_work_logs` directly rather than through [cantiereWorklogsProvider], which is
/// online-first and shaped for StepOre's hour suggestion: a history section must show what the
/// device holds, never go blank because a request failed, and needs the approval state the
/// suggestion DTO does not carry.
///
/// Only this technician's rows are stored, so "empty" here always means "this device has none of
/// your shifts for this site", never "your colleagues did not work" — the screen says the former.
final cantiereWorkLogMirrorProvider =
    StreamProvider.autoDispose.family<List<CantiereWorkLog>, String>((ref, cantiereId) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(db.cantiereWorkLogs)
            ..where((w) => w.cantiereId.equals(cantiereId))
            ..orderBy([
              (w) => OrderingTerm.desc(w.workDate),
              (w) => OrderingTerm.desc(w.startSeconds),
            ]))
          .watch();
    });

/// Tickets linked to the given cantiere (`Ticket.cantiereId == id`), for the "Tickets in questo
/// cantiere" section on CantiereDetailScreen. Local-only, like every other list in this app —
/// the technician's own ticket sync scope already determines what's available here.
final ticketsForCantiereProvider = StreamProvider.autoDispose.family<List<Ticket>, String>((
  ref,
  cantiereId,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)
        ..where((t) => t.cantiereId.equals(cantiereId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});

/// The geocoded {lat, lng} for a cantiere's address, backing `CantiereMapCard`'s embedded map.
///
/// Cache-then-geocode, not a plain geocode-on-every-open: reads `Cantieri.latitude`/`longitude`
/// first, and only calls [GeocodingService] (a real Nominatim HTTP request) when both are still
/// null, immediately persisting a successful result back to those same columns. That combination
/// is what keeps this cantiere's address from ever being geocoded more than once on this device —
/// see GeocodingService's own doc comment for why that matters (Nominatim's usage policy).
///
/// Returns null when the cantiere isn't synced locally, has no usable address, or geocoding
/// failed — `CantiereMapCard` reads null as "fall back to `AppMapCard`", not as an error to
/// surface on its own.
///
/// `FutureProvider.autoDispose.family`, not a `StreamProvider`: this does one lookup (cache, or
/// cache-then-network) per family key and has nothing further to watch afterward — the Drift row
/// it just wrote does not need to be re-read live, since nothing else in this same provider
/// instance's lifetime can change it again.
final cantiereGeocodedLocationProvider = FutureProvider.autoDispose.family<GeocodedPoint?, String>((
  ref,
  cantiereId,
) async {
  final db = ref.watch(appDatabaseProvider);
  final cantiere = await (db.select(
    db.cantieri,
  )..where((c) => c.id.equals(cantiereId))).getSingleOrNull();
  if (cantiere == null) return null;

  if (cantiere.latitude != null && cantiere.longitude != null) {
    return (lat: cantiere.latitude!, lng: cantiere.longitude!);
  }

  final address = [
    cantiere.address,
    cantiere.city,
    cantiere.postalCode,
  ].where((s) => s != null && s.isNotEmpty).join(', ');
  if (address.isEmpty) return null;

  final point = await ref.read(geocodingServiceProvider).geocode(address);
  if (point == null) return null;

  await (db.update(db.cantieri)..where((c) => c.id.equals(cantiereId))).write(
    CantieriCompanion(latitude: Value(point.lat), longitude: Value(point.lng)),
  );
  return point;
});

/// A user's CantiereWorkLog entries on one cantiere, most recent first — the cantiere-tier
/// equivalent of `ticketWorklogsProvider` (features/ticket/ticket_providers.dart). Backs StepOre's
/// cantiere-tier hours suggestion, which only applies when the report has no ticket (or the ticket
/// tier found nothing) but does have a cantiereId — and the cantiere detail's own *Timbrature*
/// section.
///
/// While offline this answers from the device instead of returning nothing (P2-6), and since the
/// sync started carrying `cantiereWorkLogs` it answers from the SERVER'S OWN ROWS mirrored in
/// `cantiere_work_logs`. That distinction is the whole point: this used to read `cantiere_punches`,
/// which is an outbox — a punch leaves it the moment it is pushed, so a technician opening the
/// screen after a sync saw nothing about yesterday. The mirror never drains; the outbox is now read
/// only for punches the mirror does not know about yet (still queued), and those are merged in by
/// `clientId` so one shift is never counted twice.
///
/// Only the signed-in user's own rows are answered from local data (the device holds nobody else's
/// punches); a request for a teammate's hours still resolves to nothing while offline, which is the
/// honest answer rather than borrowing this technician's hours.
///
/// A request that never arrived, or a server fault, answers from that same local union rather than
/// from nothing: the mirror and the phone's own clocks are still the best evidence of the hours
/// worked, and a 503 is not a statement that the technician punched no time. A 4xx still throws,
/// which every call site already renders as "no suggestion".
final cantiereWorklogsProvider = FutureProvider.autoDispose
    .family<List<CantiereWorkLogDto>, ({String userId, String cantiereId})>((ref, key) async {
      Future<List<CantiereWorkLogDto>> fromDevice() async {
        final me = await ref.watch(internalUserIdProvider.future);
        if (me == null || me != key.userId) return const [];
        final businessTime = ref.watch(businessTimeProvider);
        final db = ref.watch(appDatabaseProvider);

        final mirrored =
            await (db.select(db.cantiereWorkLogs)..where(
                  (w) => w.cantiereId.equals(key.cantiereId) & w.userId.equals(key.userId),
                ))
                .get();
        final knownClientIds = {
          for (final w in mirrored)
            if (w.clientId != null) w.clientId!,
        };

        // Punches still sitting in the outbox: the server has not seen them yet, so no mirrored row
        // exists. A closed one is a shift already worked and must stay readable.
        final intervals = await ref
            .watch(cantiereSessionRepositoryProvider)
            .getClosedIntervalsFor(key.cantiereId);

        // Shaped like `CantiereWorkLogDto.fromJson` would read off the server: the Rome-local
        // wall clock (`startTime`/`endTime` are "HH:mm:ss" strings there) and the business date,
        // so the suggestion code downstream cannot tell a local entry from a server one.
        return [
          for (final w in mirrored)
            CantiereWorkLogDto(
              id: w.id,
              cantiereId: w.cantiereId,
              // The mirror does not carry the cantiere's customer; only a suggestion and one list
              // row read this DTO and neither uses it. Empty rather than invented.
              customerId: '',
              ticketId: w.ticketId,
              userId: w.userId,
              workDate: w.workDate,
              startTime: w.startUtc != null
                  ? businessTime.formatInZone(w.startUtc!, 'HH:mm:ss')
                  : _formatSeconds(w.startSeconds),
              endTime: w.endUtc != null
                  ? businessTime.formatInZone(w.endUtc!, 'HH:mm:ss')
                  : (w.endSeconds == null ? null : _formatSeconds(w.endSeconds!)),
              description: w.description,
              duration: w.startUtc != null && w.endUtc != null
                  ? w.endUtc!.difference(w.startUtc!)
                  : (w.endSeconds == null
                        ? null
                        : Duration(seconds: w.endSeconds! - w.startSeconds)),
            ),
          for (final interval in intervals)
            if (!knownClientIds.contains(interval.clientId))
              CantiereWorkLogDto(
                id: interval.clientId,
                cantiereId: interval.cantiereId,
                customerId: interval.customerId,
                ticketId: interval.ticketId,
                userId: key.userId,
                workDate: businessTime.businessDateOf(interval.startTime),
                startTime: businessTime.formatInZone(interval.startTime, 'HH:mm:ss'),
                endTime: interval.endTime == null
                    ? null
                    : businessTime.formatInZone(interval.endTime!, 'HH:mm:ss'),
                description: interval.description,
                duration: interval.endTime?.difference(interval.startTime),
              ),
        ];
      }

      if (ref.watch(isOnlineProvider)) {
        try {
          return await ref
              .watch(cantiereWorklogApiClientProvider)
              .fetchForCantiere(userId: key.userId, cantiereId: key.cantiereId);
        } catch (e) {
          if (!isTransportOrServerFault(e)) rethrow;
        }
      }
      return fromDevice();
    });

/// `HH:mm:ss` for a seconds-into-the-day value — the wire shape `CantiereWorkLogDto.startTime`
/// carries, for a mirrored row that predates the true instants (`startUtc`/`endUtc` null).
String _formatSeconds(int seconds) {
  final h = (seconds ~/ 3600).toString().padLeft(2, '0');
  final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}
