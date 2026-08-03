import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';

/// All active materiali, alphabetical by name.
///
/// TODO(backend): `db.materiali` is never populated — no sync path and no
/// `AdminApiClient.fetchMateriali()` exist yet, so this stream is always
/// empty. See docs/api-gap-list.md § "Routes present, data path missing".
final materialiCatalogProvider =
    StreamProvider.autoDispose<List<MaterialiData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.materiali)
        ..where((m) => m.isActive.equals(true))
        ..orderBy([(m) => OrderingTerm.asc(m.name)]))
      .watch();
});

/// Distinct non-null category values from the materiali table.
final materialiCategoriesProvider =
    StreamProvider.autoDispose<List<String>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.materiali)
        ..where((m) => m.isActive.equals(true)))
      .watch()
      .map((rows) {
    final cats = rows
        .map((r) => r.category)
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return cats;
  });
});
