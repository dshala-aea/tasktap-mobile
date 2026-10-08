import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/local/checklist_read_repository.dart';
import 'package:tasktap_mobile/data/sync/checklist_reconciler.dart';
import 'package:tasktap_mobile/data/sync/checklist_sync_dto.dart';
import 'package:tasktap_mobile/domain/checklist/control_type.dart';

SyncTicketControlDto row(String id, String asset, String group, int sort, {String lineage = 'l', bool required = false, ControlType type = ControlType.checkbox}) =>
    SyncTicketControlDto(
      id: id, ticketId: 't1', prodottoAssistenzaId: asset, templateControlId: 'tc-$id',
      controlLineageId: lineage, groupId: group, label: 'Label $id', type: type,
      isRequired: required, sortOrder: sort,
    );

void main() {
  late AppDatabase db;
  late ChecklistReadRepository repo;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = ChecklistReadRepository(db);
  });
  tearDown(() => db.close());

  Future<void> apply({
    required List<SyncControlGroupDto> groups,
    required List<SyncTicketControlDto> controls,
    required List<SyncTicketAssetDto> coverage,
    required List<SyncAssetDto> assets,
  }) => applyChecklistBatch(
    db,
    ChecklistBatch(
      authoritativeTicketIds: {'t1'},
      controlGroups: groups,
      ticketControls: controls,
      ticketAssets: coverage,
      assets: assets,
    ),
  );

  SyncControlGroupDto g(String id, String name, int sort, {String? parent}) => SyncControlGroupDto(
    id: id, parentGroupId: parent, maintenanceTemplateVersionId: 'v1', name: name, sortOrder: sort,
  );

  test('groups children under their libretto, lists a child under both librettos, keeps standalone', () async {
    await apply(
      groups: [g('g', 'Sicurezza', 0)],
      controls: [row('c1', 'a', 'g', 0), row('c2', 'b', 'g', 0)],
      coverage: const [
        SyncTicketAssetDto(ticketId: 't1', prodottoAssistenzaId: 'L', maintenanceTemplateVersionId: 'v1'),
        SyncTicketAssetDto(ticketId: 't1', prodottoAssistenzaId: 'M', maintenanceTemplateVersionId: 'v1'),
        SyncTicketAssetDto(ticketId: 't1', prodottoAssistenzaId: 'a', maintenanceTemplateVersionId: 'v1'),
        SyncTicketAssetDto(ticketId: 't1', prodottoAssistenzaId: 'b', maintenanceTemplateVersionId: 'v1'),
        SyncTicketAssetDto(ticketId: 't1', prodottoAssistenzaId: 's'),
      ],
      assets: const [
        SyncAssetDto(id: 'L', name: 'Libretto Nord'),
        SyncAssetDto(id: 'M', name: 'Libretto Sud'),
        SyncAssetDto(id: 'a', name: 'Caldaia 2', librettoIds: ['L']),
        SyncAssetDto(id: 'b', name: 'Caldaia 10', librettoIds: ['L', 'M']),
        SyncAssetDto(id: 's', name: 'Pompa', serialNumber: 'SN-9'),
      ],
    );

    final tree = await repo.watchTicketChecklist('t1').first;

    expect(tree.librettos.map((l) => l.libretto.name), ['Libretto Nord', 'Libretto Sud']);
    expect(tree.librettos[0].children.map((c) => c.name), ['Caldaia 2', 'Caldaia 10'], reason: 'natural order');
    expect(tree.librettos[1].children.map((c) => c.name), ['Caldaia 10']);
    expect(tree.standalone.single.name, 'Pompa');
    expect(tree.standalone.single.matricola, 'SN-9', reason: 'falls back to the legacy serial');
    expect(tree.standalone.single.templated, isFalse);
    expect(tree.distinctAssets.length, 5);
    expect(tree.omitted, isFalse);
  });

  test('builds the group tree in display order and never drops a row whose group is unknown', () async {
    await apply(
      groups: [g('root', 'Sezione', 1), g('child', 'Sotto', 0, parent: 'root'), g('other', 'Altra', 0)],
      controls: [
        row('c2', 'a', 'child', 2),
        row('c1', 'a', 'child', 1),
        row('c3', 'a', 'other', 0),
        row('c4', 'a', 'missing-group', 0),
      ],
      coverage: const [SyncTicketAssetDto(ticketId: 't1', prodottoAssistenzaId: 'a', maintenanceTemplateVersionId: 'v1')],
      assets: const [SyncAssetDto(id: 'a', name: 'Caldaia')],
    );

    final a = (await repo.watchTicketChecklist('t1').first).standalone.single;

    expect(a.placed.map((p) => (p.$1, p.$2.id)).toList(), [
      ('Altra', 'c3'),
      ('Sezione › Sotto', 'c1'),
      ('Sezione › Sotto', 'c2'),
      ('Altri controlli', 'c4'),
    ]);
  });

  test('a retained row appears under an asset that is no longer covered', () async {
    await apply(
      groups: [g('g', 'G', 0)],
      controls: [row('c1', 'gone', 'g', 0)],
      coverage: const [],
      assets: const [SyncAssetDto(id: 'gone', name: 'Rimossa')],
    );
    final tree = await repo.watchTicketChecklist('t1').first;
    final a = tree.standalone.single;
    expect((a.name, a.coveredNow), ('Rimossa', false));
  });

  test('the omitted flag reflects the bookkeeping table', () async {
    await db.into(db.checklistOmittedTickets).insert(ChecklistOmittedTicketsCompanion.insert(ticketId: 't1'));
    final tree = await repo.watchTicketChecklist('t1').first;
    expect(tree.omitted, isTrue);
    expect(tree.hasAnything, isTrue);
  });

  test('ticket-level rows are not part of the asset tree', () async {
    await db.into(db.ticketControls).insert(
          TicketControlsCompanion.insert(
            id: 'tl', ticketId: 't1', templateControlId: 'x', controlLineageId: 'l', groupId: 'g',
            label: 'Livello ticket', type: 'Text',
          ),
        );
    expect((await repo.watchTicketChecklist('t1').first).hasAnything, isFalse);
  });

  test('stream re-emits when a row changes (server value arrives with a sync)', () async {
    await apply(
      groups: [g('g', 'G', 0)],
      controls: [row('c1', 'a', 'g', 0)],
      coverage: const [SyncTicketAssetDto(ticketId: 't1', prodottoAssistenzaId: 'a', maintenanceTemplateVersionId: 'v1')],
      assets: const [SyncAssetDto(id: 'a', name: 'A')],
    );
    final emissions = <String>[];
    final sub = repo.watchTicketChecklist('t1').listen((t) => emissions.add(t.standalone.single.controls.single.status));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await (db.update(db.ticketControls)..where((c) => c.id.equals('c1'))).write(
      const TicketControlsCompanion(status: Value('Completed')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(emissions, containsAllInOrder(['Pending', 'Completed']));
  });

  test('200 children x 15 controls build into the expected tree', () async {
    final groups = [g('g1', 'Sicurezza', 0), g('g2', 'Prestazioni', 1)];
    final controls = [
      for (var a = 0; a < 200; a++)
        for (var k = 0; k < 15; k++)
          row('c-$a-$k', 'a$a', k < 8 ? 'g1' : 'g2', k, lineage: 'l$k', required: k < 5),
    ];
    await apply(
      groups: groups,
      controls: controls,
      coverage: [
        const SyncTicketAssetDto(ticketId: 't1', prodottoAssistenzaId: 'lib'),
        for (var a = 0; a < 200; a++)
          SyncTicketAssetDto(ticketId: 't1', prodottoAssistenzaId: 'a$a', maintenanceTemplateVersionId: 'v1'),
      ],
      assets: [
        const SyncAssetDto(id: 'lib', name: 'Libretto'),
        for (var a = 0; a < 200; a++) SyncAssetDto(id: 'a$a', name: 'Caldaia ${a + 1}', librettoIds: const ['lib']),
      ],
    );

    final tree = await repo.watchTicketChecklist('t1').first;

    expect(tree.librettos.single.children.length, 200);
    expect(tree.librettos.single.children.first.name, 'Caldaia 1');
    expect(tree.librettos.single.children.last.name, 'Caldaia 200');
    expect(tree.librettos.single.children.every((c) => c.controls.length == 15), isTrue);
  });
}
