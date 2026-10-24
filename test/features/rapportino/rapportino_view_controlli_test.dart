// The sent report's Controlli section used to be one flat list whose labels came only from the
// ticket's checklist — so on a device without that checklist every row read "Controllo <guid>", and
// nothing grouped the findings by the asset they were recorded against. These tests pin the two
// things that fix: an answer carries its own name and asset, and the section groups by asset with
// the ticket-level findings first.

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/rapportino/rapportino_view_screen.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';

ReportControlliData _answer(String controlId, {String? label, String? assetId}) =>
    ReportControlliData(
      id: 'ans-$controlId',
      tenantId: 't1',
      createdAt: DateTime.utc(2026, 7, 10),
      reportId: 'r1',
      controlId: controlId,
      boolValue: true,
      controlLabel: label,
      assetId: assetId,
    );

FlatTicketControl _checklistControl(String id, {String? assetId, String label = 'Dal ticket'}) =>
    FlatTicketControl(
      groupPath: 'Gruppo',
      control: TicketControlDto(
        id: id,
        templateControlId: 'tc-$id',
        label: label,
        type: ControlType.checkbox,
        isRequired: false,
        sortOrder: 0,
        status: 'Completed',
        prodottoAssistenzaId: assetId,
      ),
    );

void main() {
  test('groups by the asset recorded with each answer, ticket-level rows first', () {
    final groups = groupControlliByAsset(
      [
        _answer('c1', label: 'Pressione', assetId: 'caldaia'),
        _answer('c2', label: 'Note generali'),
        _answer('c3', label: 'Fumi', assetId: 'caldaia'),
        _answer('c4', label: 'Filtro', assetId: 'condizionatore'),
      ],
      const {},
    );

    expect(groups.map((g) => g.assetId), [null, 'caldaia', 'condizionatore']);
    expect(groups[0].rows.map((r) => r.controlId), ['c2']);
    expect(
      groups[1].rows.map((r) => r.controlId),
      ['c1', 'c3'],
      reason: 'order inside an asset is the order the technician answered in',
    );
  });

  test('falls back to the checklist asset when the answer carries none', () {
    // Rows mirrored from the server never carry the snapshot — they were not answered here.
    final groups = groupControlliByAsset(
      [_answer('c1'), _answer('c2')],
      {
        'c1': _checklistControl('c1', assetId: 'caldaia'),
        'c2': _checklistControl('c2', assetId: 'caldaia'),
      },
    );

    expect(groups.single.assetId, 'caldaia');
    expect(groups.single.rows, hasLength(2));
  });

  test('an answer with neither snapshot nor checklist asset is a ticket-level row', () {
    final groups = groupControlliByAsset([_answer('c1')], const {});

    expect(groups.single.assetId, null);
    expect(groups.single.rows.single.controlId, 'c1');
  });
}
