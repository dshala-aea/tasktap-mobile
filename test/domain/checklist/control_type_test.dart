import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/domain/checklist/control_type.dart';

void main() {
  test('wire names round-trip for every real type', () {
    for (final wire in [
      'Text',
      'Number',
      'DateTime',
      'Checkbox',
      'TrueFalse',
      'Options',
    ]) {
      expect(controlTypeToWire(controlTypeFromWire(wire)), wire);
    }
  });

  test('an unknown or missing wire name degrades to unknown, never throws', () {
    expect(controlTypeFromWire('Slider'), ControlType.unknown);
    expect(controlTypeFromWire(null), ControlType.unknown);
  });

  test('only Checkbox and TrueFalse are boolean controls', () {
    expect(isBooleanControl(ControlType.checkbox), isTrue);
    expect(isBooleanControl(ControlType.trueFalse), isTrue);
    for (final t in [
      ControlType.text,
      ControlType.number,
      ControlType.dateTime,
      ControlType.options,
      ControlType.unknown,
    ]) {
      expect(isBooleanControl(t), isFalse, reason: '$t');
    }
  });
}
