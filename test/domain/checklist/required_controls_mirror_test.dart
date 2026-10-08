import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/domain/checklist/checklist_items.dart';
import 'package:tasktap_mobile/domain/checklist/checklist_models.dart';
import 'package:tasktap_mobile/domain/checklist/control_type.dart';
import 'package:tasktap_mobile/domain/checklist/required_controls_mirror.dart';

ChecklistControl ctl(String id, String asset, {bool required = true, bool retained = false, String status = 'Pending'}) =>
    ChecklistControl(
      id: id, ticketId: 't1', assetId: asset, templateControlId: 'tc', lineageId: 'l', groupId: 'g',
      label: 'Label $id', type: ControlType.checkbox, isRequired: required, status: status, isRetained: retained,
    );

AssetChecklist asset(String id, String name, List<ChecklistControl> c, {bool templated = true, bool covered = true}) =>
    AssetChecklist(
      assetId: id, name: name, templated: templated, coveredNow: covered,
      groups: [ChecklistGroup(id: 'g', name: 'G', controls: c)],
    );

void main() {
  test('lists unanswered required rows per asset instance, ordered by asset name then label', () {
    final tree = TicketChecklist(
      ticketId: 't1',
      standalone: [
        asset('b', 'Caldaia 10', [ctl('b1', 'b')]),
        asset('a', 'Caldaia 2', [ctl('a2', 'a'), ctl('a1', 'a'), ctl('opt', 'a', required: false)]),
      ],
    );
    final s = assetChecklistStatus(tree, (_) => null);

    expect(s.missing.map((m) => (m.assetName, m.controlId)).toList(), [
      ('Caldaia 2', 'a1'), ('Caldaia 2', 'a2'), ('Caldaia 10', 'b1'),
    ]);
    expect((s.assetCount, s.requiredTotal), (2, 3));
  });

  test('answered rows, retained rows, not-covered assets and legacy assets never count', () {
    final tree = TicketChecklist(
      ticketId: 't1',
      standalone: [
        asset('a', 'A', [ctl('a1', 'a'), ctl('a2', 'a', retained: true), ctl('a3', 'a', status: 'Completed')]),
        asset('gone', 'Rimossa', [ctl('g1', 'gone')], covered: false),
        asset('old', 'Vecchio', const [], templated: false),
      ],
    );
    final s = assetChecklistStatus(tree, (id) => id == 'a1' ? const ChecklistAnswer(boolValue: false) : null);
    expect(s.missing, isEmpty, reason: 'false answers a checkbox; the others are ignored by the gate');
  });

  test('the same child under two librettos is one instance, not two', () {
    final child = asset('b', 'Caldaia', [ctl('b1', 'b')]);
    final tree = TicketChecklist(
      ticketId: 't1',
      librettos: [
        LibrettoGroup(libretto: asset('L', 'L', const []), children: [child]),
        LibrettoGroup(libretto: asset('M', 'M', const []), children: [child]),
      ],
    );
    expect(assetChecklistStatus(tree, (_) => null).missing, hasLength(1));
  });

  test('an omitted ticket with nothing downloaded reports omitted and zero assets', () {
    final s = assetChecklistStatus(const TicketChecklist(ticketId: 't1', omitted: true), (_) => null);
    expect((s.omitted, s.assetCount), (true, 0));
    expect(s.missing, isEmpty);
  });

  test('the client mirror never answers a control from a note', () {
    final tree = TicketChecklist(ticketId: 't1', standalone: [asset('a', 'A', [ctl('a1', 'a')])]);
    expect(
      assetChecklistStatus(tree, (_) => const ChecklistAnswer(note: 'solo nota')).missing,
      hasLength(1),
    );
  });

  test('buildChecklistItems: membership follows the frozen lookup, header progress follows the live one', () {
    final tree = TicketChecklist(ticketId: 't1', standalone: [asset('a', 'A', [ctl('a1', 'a'), ctl('a2', 'a')])]);
    const answeredNow = ChecklistAnswer(boolValue: true);
    final items = buildChecklistItems(
      tree,
      const ChecklistQuery(filter: ChecklistFilter.toFill),
      (_) => null, // when the filter was applied nothing was answered
      liveProgress: (id) => id == 'a1' ? answeredNow : null,
    );
    expect(items.whereType<ControlItem>().map((c) => c.control.id), ['a1', 'a2'],
        reason: 'the row the technician just answered does not vanish under their thumb');
    expect(items.whereType<AssetHeaderItem>().single.progress.answered, 1);
  });
}
