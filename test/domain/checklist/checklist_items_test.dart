import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/domain/checklist/checklist_items.dart';
import 'package:tasktap_mobile/domain/checklist/checklist_models.dart';
import 'package:tasktap_mobile/domain/checklist/control_type.dart';

ChecklistControl ctl(
  String id,
  String asset,
  String lineage, {
  ControlType type = ControlType.checkbox,
  bool required = false,
  ChecklistAnswer stored = const ChecklistAnswer(),
  String status = 'Pending',
  bool retained = false,
}) => ChecklistControl(
  id: id, ticketId: 't1', assetId: asset, templateControlId: 'tc-$lineage', lineageId: lineage,
  groupId: 'g', label: 'Label $lineage', type: type, isRequired: required, stored: stored,
  status: status, isRetained: retained,
);

AssetChecklist asset(String id, String name, List<ChecklistControl> controls, {String? matricola}) =>
    AssetChecklist(
      assetId: id,
      name: name,
      matricola: matricola,
      templated: true,
      groups: [ChecklistGroup(id: 'g', name: 'Sicurezza', controls: controls)],
    );

void main() {
  // libretto L with children A (Caldaia 1) and B (Caldaia 2); B also sits under libretto M; one
  // standalone S.
  final a = asset('a', 'Caldaia 1', [ctl('a1', 'a', 'l1', required: true), ctl('a2', 'a', 'l2', type: ControlType.number)], matricola: 'MX-100');
  final b = asset('b', 'Caldaia 2', [ctl('b1', 'b', 'l1', required: true), ctl('b2', 'b', 'l2', type: ControlType.number)]);
  final s = asset('s', 'Pompa', [ctl('s1', 's', 'l1')]);
  final libL = asset('L', 'Libretto Nord', const []);
  final libM = asset('M', 'Libretto Sud', const []);
  final tree = TicketChecklist(
    ticketId: 't1',
    librettos: [
      LibrettoGroup(libretto: libL, children: [a, b]),
      LibrettoGroup(libretto: libM, children: [b]),
    ],
    standalone: [s],
  );

  List<String> keys(List<ChecklistListItem> items) => items.map((i) => i.key).toList();
  Iterable<ControlItem> controlsOf(List<ChecklistListItem> items) => items.whereType<ControlItem>();

  test('collapsed by asset: libretto headers, one header per placement, no control rows', () {
    final items = buildChecklistItems(tree, const ChecklistQuery(), (_) => null);

    expect(items.whereType<LibrettoHeaderItem>().map((i) => i.libretto.name), ['Libretto Nord', 'Libretto Sud']);
    expect(items.whereType<AssetHeaderItem>().map((i) => (i.asset.assetId, i.librettoId)), [
      ('a', 'L'), ('b', 'L'), ('b', 'M'), ('s', null),
    ], reason: 'a child under two librettos appears under both');
    expect(controlsOf(items), isEmpty);
  });

  test('the same child placed twice gets distinct keys (stable ValueKeys in a lazy list)', () {
    final items = buildChecklistItems(tree, const ChecklistQuery(), (_) => null);
    expect(keys(items).toSet().length, items.length);
  });

  test('distinctAssets counts a child under two librettos once', () {
    expect(tree.distinctAssets.map((x) => x.assetId).toList(), ['L', 'a', 'b', 'M', 's']);
  });

  test('an expanded asset lists its group header and controls', () {
    final items = buildChecklistItems(tree, const ChecklistQuery(expandedAssetIds: {'a'}), (_) => null);
    final control = controlsOf(items).map((c) => c.control.id).toList();
    expect(control, ['a1', 'a2']);
    expect(items.whereType<ControlGroupItem>().single.path, 'Sicurezza');
  });

  test('header progress counts every control, not only the filtered ones', () {
    final items = buildChecklistItems(
      tree,
      const ChecklistQuery(filter: ChecklistFilter.requiredMissing),
      (_) => null,
    );
    final header = items.whereType<AssetHeaderItem>().firstWhere((h) => h.asset.assetId == 'a');
    expect((header.progress.total, header.progress.requiredMissing), (2, 1));
  });

  group('filters', () {
    final local = <String, ChecklistAnswer>{
      'a1': const ChecklistAnswer(boolValue: true),
      'b1': const ChecklistAnswer(boolValue: false),
      'a2': const ChecklistAnswer(numberValue: 3, note: 'rumore'),
    };
    ChecklistAnswer? lookup(String id) => local[id];

    test('Da compilare: only unanswered controls, auto-expanded, assets with nothing left disappear', () {
      final items = buildChecklistItems(tree, const ChecklistQuery(filter: ChecklistFilter.toFill), lookup);
      expect(controlsOf(items).map((c) => c.control.id).toSet(), {'b2', 's1'});
      expect(items.whereType<AssetHeaderItem>().map((h) => h.asset.assetId).toSet(), {'b', 's'});
    });

    test('Obbligatori mancanti: unanswered AND required', () {
      final items = buildChecklistItems(tree, const ChecklistQuery(filter: ChecklistFilter.requiredMissing), lookup);
      expect(controlsOf(items), isEmpty, reason: 'a1 and b1 are both answered here');

      final none = buildChecklistItems(tree, const ChecklistQuery(filter: ChecklistFilter.requiredMissing), (_) => null);
      expect(controlsOf(none).map((c) => c.control.id).toSet(), {'a1', 'b1'});
    });

    test('Eccezioni: boolean false or a note, nothing else', () {
      final items = buildChecklistItems(tree, const ChecklistQuery(filter: ChecklistFilter.exceptions), lookup);
      expect(controlsOf(items).map((c) => c.control.id).toSet(), {'b1', 'a2'});
    });

    test('an empty filter result leaves no orphan libretto header', () {
      final items = buildChecklistItems(
        tree,
        const ChecklistQuery(filter: ChecklistFilter.exceptions),
        (_) => null,
      );
      expect(items, isEmpty);
    });

    test('retained rows are shown only in the unfiltered view', () {
      final withRetained = asset('r', 'Residuo', [ctl('r1', 'r', 'l9', retained: true)]);
      final t = TicketChecklist(ticketId: 't1', standalone: [withRetained]);
      expect(controlsOf(buildChecklistItems(t, const ChecklistQuery(expandedAssetIds: {'r'}), (_) => null)), hasLength(1));
      expect(controlsOf(buildChecklistItems(t, const ChecklistQuery(filter: ChecklistFilter.toFill), (_) => null)), isEmpty);
    });
  });

  group('text search (by asset layout: asset name or matricola)', () {
    test('matches the name case-insensitively and the matricola', () {
      expect(
        buildChecklistItems(tree, const ChecklistQuery(text: 'caldaia 2'), (_) => null)
            .whereType<AssetHeaderItem>().map((h) => h.asset.assetId).toSet(),
        {'b'},
      );
      expect(
        buildChecklistItems(tree, const ChecklistQuery(text: 'mx-100'), (_) => null)
            .whereType<AssetHeaderItem>().map((h) => h.asset.assetId),
        ['a'],
      );
    });
  });

  group('by control layout', () {
    test('one header per control lineage, then one row per asset, across librettos, deduped', () {
      final items = buildChecklistItems(
        tree,
        const ChecklistQuery(layout: ChecklistLayout.byControl),
        (_) => null,
      );
      final headers = items.whereType<ControlHeaderItem>().toList();
      expect(headers.map((h) => (h.lineageId, h.assetCount)), [('l1', 3), ('l2', 2)]);
      expect(controlsOf(items).map((c) => c.control.id).toList(), ['a1', 'b1', 's1', 'a2', 'b2']);
    });

    test('the text filter matches the control label here', () {
      final items = buildChecklistItems(
        tree,
        const ChecklistQuery(layout: ChecklistLayout.byControl, text: 'l2'),
        (_) => null,
      );
      expect(items.whereType<ControlHeaderItem>().map((h) => h.lineageId), ['l2']);
    });
  });

  test('200 assets x 15 controls: the list model is linear and complete', () {
    final children = [
      for (var i = 0; i < 200; i++)
        asset('a$i', 'Caldaia ${i + 1}', [for (var k = 0; k < 15; k++) ctl('c-$i-$k', 'a$i', 'l$k', required: k < 5)]),
    ];
    final big = TicketChecklist(
      ticketId: 't1',
      librettos: [LibrettoGroup(libretto: asset('L', 'Libretto', const []), children: children)],
    );

    final collapsed = buildChecklistItems(big, const ChecklistQuery(), (_) => null);
    expect(collapsed.length, 1 + 200, reason: 'libretto header + one header per child (the libretto has no rows of its own)');

    final toFill = buildChecklistItems(big, const ChecklistQuery(filter: ChecklistFilter.toFill), (_) => null);
    expect(toFill.whereType<ControlItem>().length, 3000);

    final byControl = buildChecklistItems(big, const ChecklistQuery(layout: ChecklistLayout.byControl), (_) => null);
    expect(byControl.whereType<ControlHeaderItem>().length, 15);
    expect(byControl.whereType<ControlItem>().length, 3000);
  });
}
