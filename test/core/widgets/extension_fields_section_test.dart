// dart format width=100
// Covers ExtensionFieldsSection's field-type dispatch (text/number/boolean/date/select, with an
// unrecognized FieldType falling back to plain text rather than crashing — see the widget's own
// class doc comment) and its save gate (disabled until something changes, then a single PUT with
// every current value).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/core/widgets/app_text_field.dart';
import 'package:tasktap_mobile/core/widgets/app_toggle.dart';
import 'package:tasktap_mobile/core/widgets/extension_fields_section.dart';
import 'package:tasktap_mobile/data/extension_fields/extension_fields_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';

class _FakeExtensionFieldsApiClient implements ExtensionFieldsApiClient {
  _FakeExtensionFieldsApiClient({required this.defs, required this.values});

  final List<ExtensionFieldDefinitionDto> defs;
  final Map<String, String> values;

  /// What the widget last tried to save — null until a save happens.
  Map<String, String>? savedValues;

  @override
  Future<List<ExtensionFieldDefinitionDto>> fetchDefinitions(String entityType) async => defs;

  @override
  Future<Map<String, String>> fetchValues(String entityType, String entityId) async => values;

  @override
  Future<void> saveValues(String entityType, String entityId, Map<String, String> values) async {
    savedValues = values;
  }
}

ExtensionFieldDefinitionDto _def({
  required String key,
  required String label,
  required String fieldType,
  bool isRequired = false,
  String? options,
  String? unit,
  int sortOrder = 0,
}) => ExtensionFieldDefinitionDto(
  id: key,
  key: key,
  label: label,
  entityType: 'ticket',
  fieldType: fieldType,
  isRequired: isRequired,
  showInCard: false,
  sortOrder: sortOrder,
  options: options,
  unit: unit,
);

Widget _wrap(ExtensionFieldsApiClient client) {
  return ProviderScope(
    overrides: [
      isOnlineProvider.overrideWithValue(true),
      extensionFieldsApiClientProvider.overrideWithValue(client),
    ],
    child: const MaterialApp(
      home: Scaffold(body: ExtensionFieldsSection(entityType: 'ticket', entityId: 'tk-1')),
    ),
  );
}

void main() {
  testWidgets('renders nothing when the tenant has no active definitions', (tester) async {
    final client = _FakeExtensionFieldsApiClient(defs: const [], values: const {});
    await tester.pumpWidget(_wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Altri campi'), findsNothing);
    expect(find.byType(AppTextField), findsNothing);
  });

  testWidgets('renders one input per definition, dispatched by FieldType', (tester) async {
    final client = _FakeExtensionFieldsApiClient(
      defs: [
        _def(key: 'note', label: 'Nota', fieldType: 'text'),
        _def(key: 'peso', label: 'Peso', fieldType: 'number', unit: 'kg', sortOrder: 1),
        _def(key: 'urgente', label: 'Urgente', fieldType: 'boolean', sortOrder: 2),
        _def(key: 'scadenza', label: 'Scadenza', fieldType: 'date', sortOrder: 3),
        _def(
          key: 'colore',
          label: 'Colore',
          fieldType: 'select',
          options: '["Rosso","Verde"]',
          sortOrder: 4,
        ),
        // Unrecognized FieldType — falls back to a plain text field.
        _def(key: 'misterioso', label: 'Misterioso', fieldType: 'wat', sortOrder: 5),
      ],
      values: const {'note': 'ciao', 'peso': '12.5', 'urgente': 'true', 'colore': 'Verde'},
    );
    await tester.pumpWidget(_wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Altri campi'), findsOneWidget);
    // text + number + unrecognized-falls-back-to-text = 3 AppTextFields.
    expect(find.byType(AppTextField), findsNWidgets(3));
    expect(find.byType(AppToggle), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
  });

  testWidgets('a select with no usable Options falls back to a plain text field', (tester) async {
    final client = _FakeExtensionFieldsApiClient(
      defs: [_def(key: 'colore', label: 'Colore', fieldType: 'select', options: null)],
      values: const {},
    );
    await tester.pumpWidget(_wrap(client));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byType(AppTextField), findsOneWidget);
  });

  testWidgets('Salva is disabled until something changes, then sends the full value set', (
    tester,
  ) async {
    final client = _FakeExtensionFieldsApiClient(
      defs: [_def(key: 'note', label: 'Nota', fieldType: 'text')],
      values: const {'note': 'vecchio'},
    );
    await tester.pumpWidget(_wrap(client));
    await tester.pumpAndSettle();

    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);

    await tester.enterText(find.byType(TextFormField), 'nuovo');
    await tester.pump();

    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);
    expect(client.savedValues, isNull);

    await tester.tap(find.byType(AppButton));
    await tester.pump();
    await tester.pump();

    expect(client.savedValues, {'note': 'nuovo'});
  });
}
