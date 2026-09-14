// dart format width=100
// lib/features/cantiere/cantiere_providers.dart
//
// Providers backing the technician-facing Cantieri tab (CantieriListScreen,
// CantiereDetailScreen). Both read the local Drift mirror only — no independent network call,
// same offline-first shape as cantieriProvider (features/timbra/cantiere_timbra_screen.dart),
// which this file's cantiereByIdProvider complements with a single-row lookup by id.

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location/geocoding_service.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart' show appDatabaseProvider;

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
