// dart format width=100
import 'package:flutter/foundation.dart';

import '../sync/sync_dto.dart';

/// One row a picker can show, from either source: the local mirror or an online search. The widget
/// cannot tell them apart, and must not — that's the point.
///
/// It is deliberately *not* a Drift row and not a wire DTO. A picker's list is a merged one — see
/// [ReferencePickerField] — so it has to be a third type that both sources can produce.
@immutable
class ReferenceOption {
  const ReferenceOption({required this.id, required this.label, this.subtitle});

  final String id;

  /// The primary line: a contract's name, a commessa's `codice`, a product's name, an agent's name.
  final String label;

  /// The secondary line, when the entity has one worth showing at a glance.
  final String? subtitle;

  /// From the *wire* DTO — the shape [ReferenceSearchClient] parses. `numero` or `codice`: a
  /// technician reads whichever is printed on the paper contract.
  factory ReferenceOption.contract(ContractSyncDto c) =>
      ReferenceOption(id: c.id, label: c.name, subtitle: c.numero ?? c.codice);

  /// From the *wire* DTO. A commessa is called by its `codice`; the description is the second line.
  factory ReferenceOption.commessa(CommessaSyncDto c) =>
      ReferenceOption(id: c.id, label: c.codice, subtitle: c.descrizione);

  /// From the *wire* DTO. Products are named by a technician ("Caldaia Nord"), so the serial or
  /// code is the distinguishing second line.
  factory ReferenceOption.prodotto(ProdottoAssistenzaSyncDto p) =>
      ReferenceOption(id: p.id, label: p.name, subtitle: p.codice ?? p.serialNumber);

  /// From the *wire* DTO. An agent is a person; the phone is what a technician actually needs.
  factory ReferenceOption.agent(AgentSyncDto a) =>
      ReferenceOption(id: a.id, label: a.nome, subtitle: a.cellulare ?? a.email);

  @override
  String toString() => 'ReferenceOption($id, $label)';
}
