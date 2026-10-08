// `isException` is also a matcher in package:matcher (re-exported by flutter_test); the domain
// function under test shadows it, so the matcher is hidden here.
import 'package:flutter_test/flutter_test.dart' hide isException;
import 'package:tasktap_mobile/domain/checklist/checklist_models.dart';
import 'package:tasktap_mobile/domain/checklist/control_answer_rules.dart';
import 'package:tasktap_mobile/domain/checklist/control_type.dart';

ChecklistControl control(
  ControlType type, {
  bool required = false,
  String status = 'Pending',
  ChecklistAnswer stored = const ChecklistAnswer(),
  bool retained = false,
  String id = 'c1',
}) => ChecklistControl(
  id: id, ticketId: 't1', assetId: 'a1', templateControlId: 'tc', lineageId: 'l', groupId: 'g',
  label: 'Controllo', type: type, isRequired: required, status: status, stored: stored,
  isRetained: retained,
);

void main() {
  group('isAnswered per type (hand-off 2.2)', () {
    test('Text and Options need a non-blank string', () {
      for (final t in [ControlType.text, ControlType.options]) {
        expect(isAnswered(control(t), const ChecklistAnswer(stringValue: 'ok')), isTrue, reason: '$t');
        expect(isAnswered(control(t), const ChecklistAnswer(stringValue: '   ')), isFalse, reason: '$t');
        expect(isAnswered(control(t), null), isFalse, reason: '$t');
      }
    });

    test('Number: 0 is an answer', () {
      expect(isAnswered(control(ControlType.number), const ChecklistAnswer(numberValue: 0)), isTrue);
      expect(isAnswered(control(ControlType.number), const ChecklistAnswer()), isFalse);
    });

    test('Checkbox and TrueFalse: false is an answer', () {
      for (final t in [ControlType.checkbox, ControlType.trueFalse]) {
        expect(isAnswered(control(t), const ChecklistAnswer(boolValue: false)), isTrue, reason: '$t');
        expect(isAnswered(control(t), const ChecklistAnswer()), isFalse, reason: '$t');
      }
    });

    test('DateTime: any value', () {
      expect(isAnswered(control(ControlType.dateTime), ChecklistAnswer(dateValue: DateTime.utc(2026, 10, 7))), isTrue);
    });

    test('a stray value in the wrong column does not answer the control', () {
      expect(isAnswered(control(ControlType.checkbox), const ChecklistAnswer(stringValue: 'sì')), isFalse);
      expect(isAnswered(control(ControlType.number), const ChecklistAnswer(boolValue: true)), isFalse);
    });

    test('a note alone is never an answer', () {
      expect(isAnswered(control(ControlType.checkbox), const ChecklistAnswer(note: 'guasto')), isFalse);
    });

    test('multi-visit: a ticket that already holds the answer counts', () {
      expect(isAnswered(control(ControlType.checkbox, status: 'Completed'), null), isTrue);
      expect(isAnswered(control(ControlType.checkbox, status: 'NotApplicable'), null), isTrue);
      expect(
        isAnswered(control(ControlType.number, stored: const ChecklistAnswer(numberValue: 3)), null),
        isTrue,
      );
    });
  });

  group('isException', () {
    test('a boolean answered false is an exception, true is not', () {
      expect(isException(control(ControlType.checkbox), const ChecklistAnswer(boolValue: false)), isTrue);
      expect(isException(control(ControlType.trueFalse), const ChecklistAnswer(boolValue: true)), isFalse);
    });

    test('any non-blank note is an exception, a blank one is not', () {
      expect(isException(control(ControlType.number), const ChecklistAnswer(note: 'perdita')), isTrue);
      expect(isException(control(ControlType.number), const ChecklistAnswer(note: '  ')), isFalse);
    });

    test('false on a non-boolean control is not an exception', () {
      expect(isException(control(ControlType.number), const ChecklistAnswer(boolValue: false)), isFalse);
    });

    test('the stored (server) answer counts when there is no local one', () {
      expect(
        isException(control(ControlType.checkbox, stored: const ChecklistAnswer(boolValue: false)), null),
        isTrue,
      );
    });

    test('a local row replaces the stored answer entirely', () {
      final c = control(ControlType.checkbox, stored: const ChecklistAnswer(boolValue: false));
      expect(isException(c, const ChecklistAnswer(boolValue: true)), isFalse);
    });
  });

  group('progressOf', () {
    test('counts answered, missing required and exceptions; retained rows are ignored', () {
      final controls = [
        control(ControlType.checkbox, id: 'c1', required: true),
        control(ControlType.checkbox, id: 'c2', required: true),
        control(ControlType.number, id: 'c3'),
        control(ControlType.checkbox, id: 'c4', required: true, retained: true),
      ];
      final local = <String, ChecklistAnswer>{
        'c1': const ChecklistAnswer(boolValue: false),
        'c3': const ChecklistAnswer(numberValue: 0, note: 'x'),
      };

      final p = progressOf(controls, (id) => local[id]);

      expect((p.total, p.answered, p.requiredMissing, p.exceptions), (3, 2, 1, 2));
      expect(p.complete, isFalse);
    });
  });

  group('describeAnswer', () {
    test('booleans, zero and fractions', () {
      expect(describeAnswer(control(ControlType.checkbox), const ChecklistAnswer(boolValue: true)), 'Sì');
      expect(describeAnswer(control(ControlType.trueFalse), const ChecklistAnswer(boolValue: false)), 'No');
      expect(describeAnswer(control(ControlType.number), const ChecklistAnswer(numberValue: 0)), '0');
      expect(describeAnswer(control(ControlType.number), const ChecklistAnswer(numberValue: 12.5)), '12.5');
      expect(describeAnswer(control(ControlType.text), const ChecklistAnswer()), isNull);
    });
  });

  test('naturalCompare orders numbers inside names numerically', () {
    final names = ['Caldaia 10', 'Caldaia 2', 'caldaia 1', 'Bruciatore 3'];
    names.sort(naturalCompare);
    expect(names, ['Bruciatore 3', 'caldaia 1', 'Caldaia 2', 'Caldaia 10']);
  });
}
