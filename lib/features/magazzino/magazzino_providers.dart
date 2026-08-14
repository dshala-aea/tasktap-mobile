import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/magazzino/magazzino_api_client.dart';
import '../../data/sync/sync_service.dart';

/// All active materiali, alphabetical by name.
///
/// The materiali catalogue, from the local mirror the sync fills — readable offline.
final materialiCatalogProvider = StreamProvider.autoDispose<List<MaterialiData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.materiali)
        ..where((m) => m.isActive.equals(true))
        ..orderBy([(m) => OrderingTerm.asc(m.name)]))
      .watch();
});

/// Current stock, straight from the server.
///
/// Not a Drift stream like the catalogue above, and not cached. A stock level is the one figure in
/// this app that is actively harmful when stale: a technician who reads "4 in stock" from Tuesday's
/// mirror and drives out without the part has been misled by the app, where "non disponibile
/// offline" would have sent them to the phone instead. So this reads through, and the screen says
/// so when it cannot.
///
/// Autodisposed and family-keyed on the search term so switching filters does not hold a stale
/// page alive behind the new one.
final giacenzeProvider = FutureProvider.autoDispose.family<PagedResult<GiacenzaDto>, GiacenzeQuery>(
  (ref, query) async {
    final client = ref.watch(magazzinoApiClientProvider);
    return client.getGiacenze(
      q: query.q,
      sottoScorta: query.soloSottoScorta ? true : null,
      pageSize: query.pageSize,
    );
  },
);

/// The arguments the giacenze list is keyed on.
///
/// A value type with real equality: a `family` keyed on a plain record or an inline object would
/// re-fetch on every rebuild, which on this screen means a network call per keystroke.
class GiacenzeQuery {
  const GiacenzeQuery({this.q, this.soloSottoScorta = false, this.pageSize = 50});

  final String? q;
  final bool soloSottoScorta;
  final int pageSize;

  @override
  bool operator ==(Object other) =>
      other is GiacenzeQuery &&
      other.q == q &&
      other.soloSottoScorta == soloSottoScorta &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(q, soloSottoScorta, pageSize);
}

/// Recent stock movements, most recent first. Same online-only reasoning as [giacenzeProvider].
final movimentiProvider = FutureProvider.autoDispose<PagedResult<MovimentoDto>>((ref) async {
  final client = ref.watch(magazzinoApiClientProvider);
  return client.getMovimenti(pageSize: 30);
});

/// Distinct non-null category values from the materiali table.
final materialiCategoriesProvider = StreamProvider.autoDispose<List<String>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.materiali)..where((m) => m.isActive.equals(true))).watch().map((rows) {
    final cats =
        rows.map((r) => r.category).whereType<String>().where((c) => c.isNotEmpty).toSet().toList()
          ..sort();
    return cats;
  });
});
