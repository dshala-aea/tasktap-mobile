// dart format width=100
// test/features/ticket/ticket_detail_api_client_test.dart
//
// Unit tests for the DTO parsing and flatten helper backing the ticket-detail
// tabs (Report / Controllo / Allegati / Fabbisogno). Widget-level coverage of
// the three outcomes (data/empty/offline) lives in ticket_detail_screen_test
// and step_materiali_fold_test; this file covers the JSON→Dart mapping in
// isolation, including the shapes that are easy to get subtly wrong (int
// enum, string enum, nested groups, unparseable Options).

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';

void main() {
  group('TicketControlDto.fromJson', () {
    test('parses ControlTypeEnum as an int, not a string', () {
      final dto = TicketControlDto.fromJson({
        'id': 'tc-1',
        'templateControlId': 'tpl-1',
        'label': 'Pressione OK',
        'type': 0,
        'isRequired': true,
        'sortOrder': 0,
        'status': 'Pending',
      });

      expect(dto.type, ControlType.checkbox);
    });

    test('maps all five ControlTypeEnum ordinals', () {
      ControlType typeFor(int ordinal) => TicketControlDto.fromJson({
            'id': 'tc-1',
            'templateControlId': 'tpl-1',
            'label': 'x',
            'type': ordinal,
            'isRequired': false,
            'sortOrder': 0,
            'status': 'Pending',
          }).type;

      expect(typeFor(0), ControlType.checkbox);
      expect(typeFor(1), ControlType.freeText);
      expect(typeFor(2), ControlType.radioOnOff);
      expect(typeFor(3), ControlType.date);
      expect(typeFor(4), ControlType.singleChoice);
    });

    test('keeps TicketControlStatus as the raw string the backend sends', () {
      final dto = TicketControlDto.fromJson({
        'id': 'tc-1',
        'templateControlId': 'tpl-1',
        'label': 'x',
        'type': 0,
        'isRequired': false,
        'sortOrder': 0,
        'status': 'Completed',
      });

      expect(dto.status, 'Completed');
    });

    test('choiceOptions parses a JSON array of strings', () {
      final dto = TicketControlDto.fromJson({
        'id': 'tc-1',
        'templateControlId': 'tpl-1',
        'label': 'x',
        'type': 4,
        'isRequired': false,
        'sortOrder': 0,
        'status': 'Pending',
        'options': '["Buono","Sufficiente","Da sostituire"]',
      });

      expect(dto.choiceOptions, ['Buono', 'Sufficiente', 'Da sostituire']);
    });

    test('choiceOptions degrades to empty (not a crash) when Options is not valid JSON', () {
      final dto = TicketControlDto.fromJson({
        'id': 'tc-1',
        'templateControlId': 'tpl-1',
        'label': 'x',
        'type': 4,
        'isRequired': false,
        'sortOrder': 0,
        'status': 'Pending',
        'options': 'not json',
      });

      expect(dto.choiceOptions, isEmpty);
    });

    test('choiceOptions is empty when Options is null', () {
      final dto = TicketControlDto.fromJson({
        'id': 'tc-1',
        'templateControlId': 'tpl-1',
        'label': 'x',
        'type': 1,
        'isRequired': false,
        'sortOrder': 0,
        'status': 'Pending',
      });

      expect(dto.choiceOptions, isEmpty);
    });
  });

  group('flattenTicketControls', () {
    test('flattens nested groups depth-first, preserving order', () {
      final groups = [
        TicketControlGroupDto.fromJson({
          'id': 'g1',
          'name': 'Sezione A',
          'sortOrder': 0,
          'controls': [
            {
              'id': 'c1',
              'templateControlId': 't1',
              'label': 'Item 1',
              'type': 1,
              'isRequired': false,
              'sortOrder': 0,
              'status': 'Pending',
            },
          ],
          'subgroups': [
            {
              'id': 'g1a',
              'name': 'Sotto A',
              'sortOrder': 0,
              'controls': [
                {
                  'id': 'c2',
                  'templateControlId': 't2',
                  'label': 'Item 2',
                  'type': 1,
                  'isRequired': false,
                  'sortOrder': 0,
                  'status': 'Pending',
                },
              ],
              'subgroups': <dynamic>[],
            },
          ],
        }),
      ];

      final flat = flattenTicketControls(groups);

      expect(flat, hasLength(2));
      expect(flat[0].control.id, 'c1');
      expect(flat[0].groupPath, 'Sezione A');
      expect(flat[1].control.id, 'c2');
      expect(flat[1].groupPath, 'Sezione A › Sotto A');
    });

    test('an empty group tree flattens to an empty list — the "no template resolved" case', () {
      expect(flattenTicketControls(const []), isEmpty);
    });
  });

  group('TicketReportSummary.fromJson', () {
    test('maps the ReportStatoEnum ordinal to its Italian label', () {
      final report = TicketReportSummary.fromJson({
        'id': 'r1',
        'title': 'Intervento',
        'stato': 2,
        'createdAt': '2026-07-01T10:00:00Z',
      });

      expect(report.statoLabel, 'Controllato');
    });
  });

  group('TicketMaterialeDto.fromJson', () {
    test('quantita parses whether the backend sends a number or a numeric string', () {
      final asNumber = TicketMaterialeDto.fromJson({
        'id': 'm1',
        'nome': 'Valvola',
        'quantita': 2.5,
        'disponibile': true,
      });
      final asString = TicketMaterialeDto.fromJson({
        'id': 'm1',
        'nome': 'Valvola',
        'quantita': '2.5',
        'disponibile': true,
      });

      expect(asNumber.quantita, 2.5);
      expect(asString.quantita, 2.5);
    });

    test('nome falls back to the free-text row when the catalogue code is null', () {
      final dto = TicketMaterialeDto.fromJson({
        'id': 'm1',
        'materialeId': null,
        'codice': null,
        'nome': 'Guarnizione generica',
        'quantita': 1,
        'disponibile': false,
      });

      expect(dto.codice, isNull);
      expect(dto.nome, 'Guarnizione generica');
      expect(dto.disponibile, isFalse);
    });
  });
}
