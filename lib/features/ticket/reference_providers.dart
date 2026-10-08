// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dio_client.dart';
import '../../data/reference/reference_cache_repository.dart';
import '../../data/reference/reference_option.dart';
import '../../data/reference/reference_search_client.dart';

/// The online half of every reference picker: one search client over the shared [Dio] and the one
/// mirror repository, so a row a search found is stored by exactly the code that stores the sync's
/// rows.
///
/// A screen reads this to build the `search:` callback it hands [ReferencePickerField]. The widget
/// never sees this provider, which is what keeps "materialise before you can pick" out of the
/// render tree.
final referenceSearchClientProvider = Provider<ReferenceSearchClient>(
  (ref) => ReferenceSearchClient(ref.watch(dioProvider), ref.watch(referenceCacheProvider)),
);

/// The local half of every reference picker: what this device already has, for one customer.
/// The search half is built at the call site from [referenceSearchClientProvider], so a screen can
/// hand the picker a callback without the picker learning where results come from.
///
/// The family key is the customerId — the picker is scoped to the customer the technician picked,
/// and the mirror is scoped the same way (see [ReferenceCacheRepository.contractsForCustomer]).
final localContractsProvider = FutureProvider.family<List<ReferenceOption>, String>((
  ref,
  customerId,
) async {
  final rows = await ref.watch(referenceCacheProvider).contractsForCustomer(customerId);
  return [
    for (final r in rows) ReferenceOption(id: r.id, label: r.name, subtitle: r.numero ?? r.codice),
  ];
});

/// As [localContractsProvider], for the customer's commesse.
final localCommesseProvider = FutureProvider.family<List<ReferenceOption>, String>((
  ref,
  customerId,
) async {
  final rows = await ref.watch(referenceCacheProvider).commesseForCustomer(customerId);
  return [
    for (final r in rows) ReferenceOption(id: r.id, label: r.codice, subtitle: r.descrizione),
  ];
});

/// As [localContractsProvider], for the customer's products under assistance.
final localProdottiProvider = FutureProvider.family<List<ReferenceOption>, String>((
  ref,
  customerId,
) async {
  final rows = await ref.watch(referenceCacheProvider).prodottiForCustomer(customerId);
  return [
    for (final r in rows)
      ReferenceOption(id: r.id, label: r.name, subtitle: r.codice ?? r.serialNumber),
  ];
});

/// The mirrored agents. Takes the same query-string family key as its siblings — `''` at every call
/// site — because agents are not scoped to a customer and the key is simply ignored: this returns
/// every active agent the device holds. The family shape is kept only so a screen can wire the four
/// pickers identically.
final localAgentsProvider = FutureProvider.family<List<ReferenceOption>, String>((ref, _) async {
  final rows = await ref.watch(referenceCacheProvider).activeAgents();
  return [
    for (final r in rows)
      ReferenceOption(id: r.id, label: r.nome, subtitle: r.cellulare ?? r.email),
  ];
});
