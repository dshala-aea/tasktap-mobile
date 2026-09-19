import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/sync_service.dart';

/// All customers (active + inactive) for admin list.
final adminCustomersProvider = StreamProvider.autoDispose<List<Customer>>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(
    db.customers,
  )..orderBy([(c) => OrderingTerm.asc(c.companyName)])).watch();
});

/// Single customer by id for admin detail/edit.
final adminCustomerDetailProvider = StreamProvider.autoDispose
    .family<Customer?, String>((ref, id) {
      final db = ref.watch(appDatabaseProvider);
      return (db.select(
        db.customers,
      )..where((c) => c.id.equals(id))).watchSingleOrNull();
    });
