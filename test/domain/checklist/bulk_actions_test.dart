import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/domain/checklist/bulk_actions.dart';
import 'package:tasktap_mobile/domain/checklist/checklist_models.dart';
import 'package:tasktap_mobile/domain/checklist/control_type.dart';

ChecklistControl ctl(
  String id,
  String asset,
  String lineage, {
  ControlType type = ControlType.checkbox,
  ChecklistAnswer stored = const ChecklistAnswer(),
  bool retained = false,
  String templateControlId = 'tc',
}) => ChecklistControl(
  id: id, ticketId: 't1', assetId: asset, templateControlId: templateControlId, lineageId: lineage,
  groupId: 'g', label: 'Label $lineage', type: type, stored: stored, isRetained: retained,
);

AssetChecklist asset(String id, List<ChecklistControl> c, {bool templated = true, bool covered = true}) =>
    AssetChecklist(
      assetId: id, name: 'Asset $id', templated: templated, coveredNow: covered,
      groups: [ChecklistGroup(id: 'g', name: 'G', controls: c)],
    );

TicketChecklist tree(List<AssetChecklist> assets) => TicketChecklist(ticketId: 't1', standalone: assets);

void main() {
  final threeAssets = tree([
    asset('a', [ctl('a1', 'a', 'ctrl'), ctl('a2', 'a', 'num', type: ControlType.number)]),
    asset('b', [ctl('b1', 'b', 'ctrl'), ctl('b2', 'b', 'num', type: ControlType.number)]),
    // pinned to ANOTHER template version: different templateControlId, same lineage
    asset('c', [ctl('c1', 'c', 'ctrl', templateControlId: 'tc-v2')]),
  ]);

  test('"segna controllato" sets the boolean on every selected asset, version-independently', () {
    final plan = planBulk(
      request: const BulkRequest(assetIds: {'a', 'b', 'c'}, lineageIds: {'ctrl'}, boolValue: true),
      tree: threeAssets,
      existing: const {},
    );

    expect(plan.rejected, isFalse);
    expect(plan.changes.map((c) => c.control.id), ['a1', 'b1', 'c1']);
    expect(plan.changes.every((c) => c.next.boolValue == true), isTrue);
    expect(plan.changes.every((c) => c.next.stringValue == null && c.next.numberValue == null), isTrue,
        reason: 'only the column matching the type is written');
  });

  test('a boolean set skips non-boolean controls and counts them', () {
    final plan = planBulk(
      request: const BulkRequest(assetIds: {'a', 'b'}, lineageIds: {'num'}, boolValue: true),
      tree: threeAssets,
      existing: const {},
    );
    expect(plan.changes, isEmpty);
    expect(plan.skippedNonBoolean, 2);
  });

  test('a note works on any control type and does not touch the answer', () {
    final plan = planBulk(
      request: const BulkRequest(assetIds: {'a'}, lineageIds: {'num'}, appendNote: 'verificato a vista'),
      tree: threeAssets,
      existing: {'a2': const ChecklistAnswer(numberValue: 3)},
    );
    final change = plan.changes.single;
    expect(change.next.note, 'verificato a vista');
    expect(change.next.numberValue, 3, reason: 'the existing answer travels, it is not replaced');
    expect(change.previous?.numberValue, 3);
  });

  test('a note is appended after a newline to the local note, then to the stored one; never overwritten', () {
    final withStored = tree([
      asset('a', [ctl('a1', 'a', 'ctrl', stored: const ChecklistAnswer(boolValue: true, note: 'visita 1'))]),
      asset('b', [ctl('b1', 'b', 'ctrl')]),
    ]);
    final plan = planBulk(
      request: const BulkRequest(assetIds: {'a', 'b'}, lineageIds: {'ctrl'}, appendNote: 'ok'),
      tree: withStored,
      existing: {'b1': const ChecklistAnswer(note: 'locale')},
    );
    expect(plan.changes.map((c) => c.next.note).toList(), ['visita 1\nok', 'locale\nok']);
    expect(plan.changes.first.next.boolValue, true, reason: 'the stored answer is kept');
  });

  test('a note that would pass 2000 characters skips that pair and reports it', () {
    final long = 'x' * 1990;
    final plan = planBulk(
      request: const BulkRequest(assetIds: {'a', 'b'}, lineageIds: {'ctrl'}, appendNote: 'abcdefghijklmnop'),
      tree: threeAssets,
      existing: {'a1': ChecklistAnswer(note: long)},
    );
    expect(plan.changes.map((c) => c.control.id), ['b1']);
    expect(plan.problems.single.code, BulkProblemCode.noteTooLong);
    expect(plan.problems.single.assetId, 'a');
  });

  test('a note of exactly the 2000-character limit is accepted (boundary is > not >=)', () {
    final plan = planBulk(
      request: BulkRequest(assetIds: const {'a'}, lineageIds: const {'ctrl'}, appendNote: 'x' * 2000),
      tree: threeAssets,
      existing: const {},
    );
    expect(plan.rejected, isFalse);
    expect(plan.problems, isEmpty);
    expect(plan.changes.single.next.note!.length, 2000);
  });

  test('a note append on an unknown-type control keeps a stored answer in any column', () {
    // A wire type this build does not recognise can hold its answer in numberValue/dateValue/
    // boolValue; appending a note must add the note and leave the answer alone.
    final t = tree([
      asset('a', [
        ctl('a1', 'a', 'u', type: ControlType.unknown, stored: const ChecklistAnswer(numberValue: 7)),
      ]),
    ]);
    final plan = planBulk(
      request: const BulkRequest(assetIds: {'a'}, lineageIds: {'u'}, appendNote: 'nota'),
      tree: t,
      existing: const {},
    );
    final next = plan.changes.single.next;
    expect(next.note, 'nota');
    expect(next.numberValue, 7, reason: 'the stored answer is not destroyed by a note-only bulk');
  });

  test('a request that does nothing is rejected', () {
    final plan = planBulk(
      request: const BulkRequest(assetIds: {'a'}, lineageIds: {'ctrl'}, appendNote: '   '),
      tree: threeAssets,
      existing: const {},
    );
    expect(plan.rejected, isTrue);
    expect(plan.problems.single.code, BulkProblemCode.emptyAction);
  });

  test('no assets or no controls selected is rejected', () {
    expect(
      planBulk(request: const BulkRequest(assetIds: {}, lineageIds: {'ctrl'}, boolValue: true), tree: threeAssets, existing: const {})
          .problems.single.code,
      BulkProblemCode.noSelection,
    );
    expect(
      planBulk(request: const BulkRequest(assetIds: {'a'}, lineageIds: {}, boolValue: true), tree: threeAssets, existing: const {})
          .problems.single.code,
      BulkProblemCode.noSelection,
    );
  });

  test('more than 5000 assets x controls is rejected before any pair work', () {
    final plan = planBulk(
      request: BulkRequest(assetIds: {for (var i = 0; i < 5001; i++) 'x$i'}, lineageIds: const {'ctrl'}, boolValue: true),
      tree: threeAssets,
      existing: const {},
    );
    expect(plan.rejected, isTrue);
    expect(plan.problems.single.code, BulkProblemCode.tooLarge);
  });

  test('exactly 5000 assets x controls is accepted (boundary is > not >=)', () {
    final plan = planBulk(
      request: BulkRequest(assetIds: {for (var i = 0; i < 5000; i++) 'x$i'}, lineageIds: const {'ctrl'}, boolValue: true),
      tree: threeAssets,
      existing: const {},
    );
    expect(plan.rejected, isFalse);
    expect(plan.problems, isEmpty);
  });

  test('assets without that control, legacy assets, removed assets and retained rows are skipped, not fatal', () {
    final t = tree([
      asset('a', [ctl('a1', 'a', 'ctrl')]),
      asset('legacy', const [], templated: false),
      asset('gone', [ctl('g1', 'gone', 'ctrl')], covered: false),
      asset('r', [ctl('r1', 'r', 'ctrl', retained: true)]),
      asset('other', [ctl('o1', 'other', 'different')]),
    ]);
    final plan = planBulk(
      request: const BulkRequest(assetIds: {'a', 'legacy', 'gone', 'r', 'other', 'unknown'}, lineageIds: {'ctrl'}, boolValue: true),
      tree: t,
      existing: const {},
    );
    expect(plan.changes.map((c) => c.control.id), ['a1']);
    expect(plan.notApplicable, 5);
  });

  test('previous is the local row when there was one, null otherwise (the undo contract)', () {
    final plan = planBulk(
      request: const BulkRequest(assetIds: {'a', 'b'}, lineageIds: {'ctrl'}, boolValue: false),
      tree: threeAssets,
      existing: {'a1': const ChecklistAnswer(boolValue: true)},
    );
    expect(plan.changes[0].previous?.boolValue, true);
    expect(plan.changes[1].previous, isNull);
  });

  test('lineage options list booleans first-class and count the assets that have them', () {
    final options = bulkLineageOptions(threeAssets, {'a', 'b', 'c'});
    final ctrl = options.firstWhere((o) => o.lineageId == 'ctrl');
    final num = options.firstWhere((o) => o.lineageId == 'num');
    expect((ctrl.isBoolean, ctrl.assetCount, num.isBoolean, num.assetCount), (true, 3, false, 2));
  });

  test('200 assets x 15 controls: one plan, linear, exact', () {
    final big = tree([
      for (var a = 0; a < 200; a++)
        asset('a$a', [
          for (var k = 0; k < 15; k++)
            ctl('c-$a-$k', 'a$a', 'l$k', type: k < 10 ? ControlType.checkbox : ControlType.number),
        ]),
    ]);
    final ids = {for (var a = 0; a < 200; a++) 'a$a'};

    final checkAll = planBulk(
      request: BulkRequest(assetIds: ids, lineageIds: {for (var k = 0; k < 10; k++) 'l$k'}, boolValue: true),
      tree: big,
      existing: const {},
    );
    expect(checkAll.affected, 2000);

    final noteAll = planBulk(
      request: BulkRequest(assetIds: ids, lineageIds: {for (var k = 0; k < 15; k++) 'l$k'}, appendNote: 'ok'),
      tree: big,
      existing: const {},
    );
    expect(noteAll.affected, 3000);

    final mixed = planBulk(
      request: BulkRequest(assetIds: ids, lineageIds: {for (var k = 0; k < 15; k++) 'l$k'}, boolValue: true),
      tree: big,
      existing: const {},
    );
    expect((mixed.affected, mixed.skippedNonBoolean), (2000, 1000));
  });

  test('problem messages are Italian and name the count', () {
    expect(describeBulkProblem(const BulkProblem(code: BulkProblemCode.emptyAction)), contains('azione'));
    expect(describeBulkProblem(const BulkProblem(code: BulkProblemCode.noteTooLong), count: 4), contains('4'));
  });
}
