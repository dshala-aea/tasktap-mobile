// dart format width=100
// The single definition of what a rapportino's custom field effectively holds — shared by the form,
// the pre-submit check and the submit payload so they cannot disagree.
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/extension_fields/extension_fields_api_client.dart';
import 'package:tasktap_mobile/domain/reports/draft_validation.dart';
import 'package:tasktap_mobile/domain/reports/extension_values.dart';

ExtensionFieldDefinitionDto _def(
  String key, {
  bool required = false,
  String? defaultValue,
  int sortOrder = 0,
  String? label,
}) => ExtensionFieldDefinitionDto(
  id: key,
  key: key,
  label: label ?? key,
  entityType: 'report',
  fieldType: 'text',
  isRequired: required,
  showInCard: false,
  sortOrder: sortOrder,
  defaultValue: defaultValue,
);

void main() {
  group('effectiveExtensionValues', () {
    test('stored value wins, else the default, else empty', () {
      final defs = [_def('zona', defaultValue: 'Nord'), _def('note', defaultValue: 'x'), _def('b')];

      expect(effectiveExtensionValues(defs, {'zona': 'Sud'}), {'zona': 'Sud', 'note': 'x', 'b': ''});
    });

    test('an explicitly cleared value stays cleared — it does not fall back to the default', () {
      expect(effectiveExtensionValues([_def('zona', defaultValue: 'Nord')], {'zona': ''}), {
        'zona': '',
      });
    });

    test('keys with no active definition are dropped', () {
      expect(effectiveExtensionValues([_def('zona')], {'zona': 'a', 'vecchio': 'b'}), {'zona': 'a'});
    });
  });

  group('missingRequiredExtensionLabels', () {
    test('lists blank required fields in the office order, by label', () {
      final defs = [
        _def('b', required: true, sortOrder: 2, label: 'Beta'),
        _def('a', required: true, sortOrder: 1, label: 'Alfa'),
        _def('c', sortOrder: 3, label: 'Gamma'),
      ];

      expect(missingRequiredExtensionLabels(defs, const {}), ['Alfa', 'Beta']);
    });

    test('a default satisfies a required field; whitespace does not', () {
      final defs = [
        _def('a', required: true, defaultValue: 'ok', label: 'Alfa'),
        _def('b', required: true, label: 'Beta'),
      ];

      expect(missingRequiredExtensionLabels(defs, {'b': '   '}), ['Beta']);
    });

    test('nothing is missing when every required field has a value', () {
      expect(missingRequiredExtensionLabels([_def('a', required: true)], {'a': 'v'}), isEmpty);
    });
  });

  group('DraftValidationResult.withMissingExtensionFields', () {
    const base = DraftValidationResult(issues: []);

    test('no missing labels leaves the result valid', () {
      expect(base.withMissingExtensionFields(const []).isValid, isTrue);
    });

    test('missing labels block the submit and name the fields', () {
      final result = base.withMissingExtensionFields(const ['Zona', 'Lotto']);

      expect(result.isValid, isFalse);
      expect(result.italianMessages, ['Campi aggiuntivi obbligatori: Zona, Lotto']);
    });

    test('keeps the issues it already had', () {
      const withIssue = DraftValidationResult(issues: [DraftValidationIssue.missingTitle]);

      final result = withIssue.withMissingExtensionFields(const ['Zona']);

      expect(result.issues, hasLength(2));
      expect(result.italianMessages.first, 'Titolo mancante');
    });
  });
}
