// dart format width=100
import 'dart:convert';

import '../local/app_database.dart';

/// What the tenant is entitled to, as last confirmed by the server.
class Entitlement {
  const Entitlement({
    required this.features,
    required this.capabilities,
    required this.seatType,
    required this.fetchedAt,
  });

  /// Granted module keys — `rapportini`, `magazzino`, and so on.
  final Set<String> features;

  /// Canonical `module.resource.action` keys.
  final Set<String> capabilities;

  /// `field` (mobile-only seat) or `office`.
  final String seatType;

  /// When the server last confirmed this. For display only — never used to expire the row.
  final DateTime fetchedAt;

  bool get isFieldSeat => seatType == 'field';
}

/// Reads and writes the cached entitlement.
///
/// **The asymmetry is the design.** Writes happen only on a successful `/api/Auth/me`; nothing
/// clears the row, and nothing expires it. A technician who loses signal — or whose token refresh
/// fails, or who is on a site with no coverage for a week — keeps working under the entitlements
/// they had. Expiring the cache to "denied" would mean a lapsed network costs them the day, which
/// is a far worse outcome than a tenant briefly retaining a module they stopped paying for. The
/// server is still the enforcement point; this only decides what the app offers.
///
/// This mirrors the rule already established for `availableActions`: no answer means allow, because
/// the alternative is refusing a technician their own work on the strength of missing information.
class EntitlementRepository {
  EntitlementRepository(this._db);

  final AppDatabase _db;

  static const _rowId = 'current';

  /// The always-on modules. Enforced true in code on the server too (`ModuleKeys.AlwaysOn`), so a
  /// client that gated them off would hide screens the backend would happily serve.
  static const alwaysOn = {'clienti', 'team', 'sistema'};

  /// What a field seat can always do, used before the first sync ever completes.
  ///
  /// A fresh install that cannot reach the network must not be a brick. These are the three things
  /// a field seat exists for; offering them unverified is right, because a technician standing in
  /// front of a customer needs to record the work either way and the server will reject anything
  /// the tenant genuinely lacks.
  static const fieldSeatBaseline = {'rapportini', 'presenze', 'interventi'};

  Future<Entitlement?> read() async {
    final row = await (_db.select(_db.entitlements)
          ..where((e) => e.id.equals(_rowId)))
        .getSingleOrNull();

    if (row == null) return null;

    return Entitlement(
      features: _decode(row.featuresJson),
      capabilities: _decode(row.capabilitiesJson),
      seatType: row.seatType,
      fetchedAt: row.fetchedAt,
    );
  }

  /// Replaces the cached entitlement. Call only after the server has actually answered.
  Future<void> write({
    required List<String> features,
    required List<String> capabilities,
    required String seatType,
    required DateTime fetchedAt,
  }) async {
    await _db.into(_db.entitlements).insertOnConflictUpdate(
          EntitlementsCompanion.insert(
            id: _rowId,
            featuresJson: jsonEncode(features),
            capabilitiesJson: jsonEncode(capabilities),
            seatType: seatType,
            fetchedAt: fetchedAt,
          ),
        );
  }

  /// Whether a module should be offered.
  ///
  /// Returns true when nothing has been cached yet and the module is in the field-seat baseline —
  /// see [fieldSeatBaseline]. Always true for [alwaysOn], matching the server.
  Future<bool> hasFeature(String moduleKey) async {
    if (alwaysOn.contains(moduleKey)) return true;

    final cached = await read();
    if (cached == null) return fieldSeatBaseline.contains(moduleKey);

    return cached.features.contains(moduleKey);
  }

  /// Whether a specific `module.resource.action` capability is held.
  ///
  /// Unlike [hasFeature] this denies when nothing is cached. A capability is finer-grained than a
  /// module and there is no safe baseline to guess at — offering an action the user may not hold
  /// would queue work the server will reject, which loses it later rather than refusing it now.
  Future<bool> hasCapability(String key) async {
    final cached = await read();
    return cached?.capabilities.contains(key) ?? false;
  }

  Set<String> _decode(String json) {
    final decoded = jsonDecode(json);
    return decoded is List ? decoded.cast<String>().toSet() : <String>{};
  }
}
