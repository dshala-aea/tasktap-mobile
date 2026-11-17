// dart format width=100
// Tests for ticket_controls_mirror.dart: the mirror → TicketControlGroupDto tree the Controllo tab
// renders when it cannot (or need not) reach the network.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/local/checklist_read_repository.dart';
import 'package:tasktap_mobile/data/sync/checklist_reconciler.dart';
import 'package:tasktap_mobile/data/sync/checklist_sync_dto.dart';
import 'package:tasktap_mobile/features/ticket/ticket_controls_mirror.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';

void main() {
  late AppDatabase db;
  late ChecklistReadRepository repo;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = ChecklistReadRepository(db);
  });
  tearDown(() => db.close());

  SyncControlGroupDto group(String id, String name, int sort, {String? parent}) =>
      SyncControlGroupDto(
        id: id,
        parentGroupId: parent,
        maintenanceTemplateVersionId: 'v1',
        name: name,
        sortOrder: sort,
      );

  SyncTicketControlDto control(
    String id,
    String groupId,
    String label, {
    String? asset,
    int sort = 0,
    ControlType type = ControlType.checkbox,
    bool required = false,
    String? description,
    String? options,
    String status = 'Pending',
    String? stringValue,
    bool? boolValue,
    DateTime? dateValue,
    double? numberValue,
    String? note,
  }) => SyncTicketControlDto(
    id: id,
    ticketId: 't1',
    prodottoAssistenzaId: asset,
    templateControlId: 'tpl-$id',
    controlLineageId: 'lin-$id',
    groupId: groupId,
    label: label,
    description: description,
    type: type,
    isRequired: required,
    options: options,
    sortOrder: sort,
    status: status,
    stringValue: stringValue,
    boolValue: boolValue,
    dateValue: dateValue,
    numberValue: numberValue,
    note: note,
  );

  Future<void> apply({
    required List<SyncControlGroupDto> groups,
    required List<SyncTicketControlDto> controls,
  }) => applyChecklistBatch(
    db,
    ChecklistBatch(
      authoritativeTicketIds: {'t1'},
      controlGroups: groups,
      ticketControls: controls,
      ticketAssets: const [],
      assets: const [],
    ),
  );

  /// The tree as the provider builds it: through the repository's own raw readers.
  Future<List<TicketControlGroupDto>> mirrorTree() async {
    final controls = await repo.watchTicketControlRows('t1').first;
    final groups = await repo.watchControlGroups().first;
    return ticketControlGroupsFromMirror(controls: controls, groups: groups);
  }

  test('nested groups become subgroups; roots are the groups with no parent', () async {
    await apply(
      groups: [
        group('sez', 'Sicurezza', 1),
        group('sub', 'Pressioni', 0, parent: 'sez'),
        group('prest', 'Prestazioni', 0),
      ],
      controls: [
        control('c1', 'sez', 'Check generale'),
        control('c2', 'sub', 'Pressione caldaia'),
        control('c3', 'prest', 'Rendimento'),
      ],
    );

    final tree = await mirrorTree();

    expect(tree.map((g) => g.name), ['Prestazioni', 'Sicurezza'], reason: 'sortOrder first');
    final sicurezza = tree.last;
    expect(sicurezza.controls.map((c) => c.label), ['Check generale']);
    expect(sicurezza.subgroups.single.name, 'Pressioni');
    expect(sicurezza.subgroups.single.controls.single.label, 'Pressione caldaia');
    expect(tree.first.controls.single.label, 'Rendimento');
  });

  test('controls are ordered by sortOrder then label within their group', () async {
    await apply(
      groups: [group('g', 'Sezione', 0)],
      controls: [
        control('c3', 'g', 'Primo', sort: 2),
        control('c2', 'g', 'Controllo 10', sort: 0),
        control('c1', 'g', 'Controllo 2', sort: 0),
      ],
    );

    final tree = await mirrorTree();

    expect(tree.single.controls.map((c) => c.label), ['Controllo 2', 'Controllo 10', 'Primo']);
  });

  test('every mirrored TicketControlDto field is mapped; valoreLimite has no source', () async {
    final answeredAt = DateTime.utc(2026, 5, 4, 9, 30);
    await apply(
      groups: [group('g', 'Sezione', 0)],
      controls: [
        control(
          'c1',
          'g',
          'Temperatura',
          sort: 3,
          type: ControlType.number,
          required: true,
          description: 'Dopo il ciclo',
          options: '["a","b"]',
          status: 'Completed',
          stringValue: 'ok',
          boolValue: true,
          dateValue: answeredAt,
          numberValue: 42.5,
          note: 'Nota del tecnico',
        ),
      ],
    );

    final dto = (await mirrorTree()).single.controls.single;

    expect(dto.id, 'c1');
    expect(dto.templateControlId, 'tpl-c1');
    expect(dto.label, 'Temperatura');
    expect(dto.description, 'Dopo il ciclo');
    expect(dto.type, ControlType.number);
    expect(dto.isRequired, isTrue);
    expect(dto.options, '["a","b"]');
    expect(dto.sortOrder, 3);
    expect(dto.status, 'Completed');
    expect(dto.stringValue, 'ok');
    expect(dto.boolValue, isTrue);
    expect(dto.dateValue, answeredAt);
    expect(dto.numberValue, 42.5);
    expect(dto.controlLineageId, 'lin-c1');
    expect(dto.note, 'Nota del tecnico');
    expect(
      dto.prodottoAssistenzaId,
      isNull,
      reason: 'the ticket-level tree holds only rows with no asset',
    );
    expect(
      dto.valoreLimite,
      isNull,
      reason: 'the sync payload carries no valoreLimite — the mirror must not invent one',
    );
    expect(dto.choiceOptions, ['a', 'b']);
  });

  test('ticket-level rows are part of the tree with a null prodottoAssistenzaId', () async {
    await apply(
      groups: [group('g', 'Sezione', 0)],
      controls: [control('tl', 'g', 'Livello ticket')],
    );

    final dto = (await mirrorTree()).single.controls.single;

    expect(dto.label, 'Livello ticket');
    expect(dto.prodottoAssistenzaId, isNull);
  });

  test('per-asset rows are not part of the ticket-level tree', () async {
    await apply(
      groups: [group('g', 'Sezione', 0)],
      controls: [
        control('tl', 'g', 'Livello ticket'),
        control('asset-row', 'g', 'Controllo di un asset', asset: 'asset-1'),
      ],
    );

    // `fetchControls` returns the ticket-level groups; the asset rows belong to the asset card, and
    // must not be listed a second time in the flat list.
    final tree = await mirrorTree();

    expect(tree.single.controls.map((c) => c.id), ['tl']);
  });

  test('only groups used by this ticket appear, even though the table is shared', () async {
    await apply(
      groups: [group('mine', 'Mia', 0)],
      controls: [control('c1', 'mine', 'Solo mia')],
    );
    // Inserted straight into the table: a group another ticket's template version uses. The batch's
    // own prune would delete it, and this test is about the mapper narrowing the shared table.
    await db
        .into(db.controlGroups)
        .insert(
          ControlGroupsCompanion.insert(
            id: 'theirs',
            maintenanceTemplateVersionId: 'v2',
            name: 'Di un altro template',
            sortOrder: 1,
          ),
        );

    final tree = await mirrorTree();

    expect(tree.map((g) => g.name), ['Mia']);
  });

  test('a row whose group never arrived is kept in a fallback section', () async {
    await apply(
      groups: [group('g', 'Sezione', 0)],
      controls: [control('c1', 'g', 'Normale'), control('orphan', 'gone', 'Senza gruppo')],
    );

    final tree = await mirrorTree();

    expect(tree.map((g) => g.name), ['Sezione', 'Altri controlli']);
    expect(tree.last.controls.single.id, 'orphan');
  });
}
