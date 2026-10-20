// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/ticket/control_group_accordion.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';

TicketControlDto _control(String id, {String status = 'Pending'}) => TicketControlDto(
  id: id,
  templateControlId: 't-$id',
  label: 'Controllo $id',
  type: ControlType.checkbox,
  isRequired: false,
  sortOrder: 0,
  status: status,
);

TicketControlGroupDto _group(
  String id,
  String name, {
  List<TicketControlDto> controls = const [],
  List<TicketControlGroupDto> subgroups = const [],
}) => TicketControlGroupDto(
  id: id,
  name: name,
  sortOrder: 0,
  controls: controls,
  subgroups: subgroups,
);

Future<void> _pump(
  WidgetTester tester,
  List<TicketControlGroupDto> groups, {
  int? collapseAbove = kControlGroupCollapseAbove,
  String? Function(List<TicketControlDto>)? summaryFor,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ControlGroupAccordion(
          groups: groups,
          collapseAbove: collapseAbove,
          summaryFor: summaryFor,
          controlBuilder: (f) => Text('${f.groupPath} | ${f.control.label}'),
        ),
      ),
    ),
  ),
);

void main() {
  final nested = [
    _group(
      'g1',
      'Impianto',
      controls: [_control('a')],
      subgroups: [
        _group('g2', 'Quadro', controls: [_control('b', status: 'Completed')]),
      ],
    ),
  ];

  testWidgets('a short checklist starts open and shows each control with its section path', (
    tester,
  ) async {
    await _pump(tester, nested);

    expect(find.text('Impianto | Controllo a'), findsOneWidget);
    expect(find.text('Impianto › Quadro | Controllo b'), findsOneWidget);
    expect(find.text('Espandi tutto'), findsNothing);
  });

  testWidgets('a long checklist starts collapsed; a section opens on its own header', (
    tester,
  ) async {
    final many = [
      _group('g1', 'Impianto', controls: [for (var i = 0; i < 11; i++) _control('c$i')]),
      _group('g2', 'Locale', controls: [_control('z')]),
    ];
    await _pump(tester, many);

    expect(find.text('Impianto | Controllo c0'), findsNothing);
    await tester.tap(find.text('Impianto'));
    await tester.pump();
    expect(find.text('Impianto | Controllo c0'), findsOneWidget);
    expect(find.text('Locale | Controllo z'), findsNothing);

    await tester.tap(find.text('Espandi tutto'));
    await tester.pump();
    expect(find.text('Locale | Controllo z'), findsOneWidget);
    await tester.tap(find.text('Comprimi tutto'));
    await tester.pump();
    expect(find.text('Impianto | Controllo c0'), findsNothing);
  });

  testWidgets('collapseAbove: null never collapses by default (the fill-in form)', (tester) async {
    final many = [
      _group('g1', 'Impianto', controls: [for (var i = 0; i < 30; i++) _control('c$i')]),
    ];
    await _pump(tester, many, collapseAbove: null);

    expect(find.text('Impianto | Controllo c0'), findsOneWidget);
    expect(find.text('Espandi tutto'), findsNothing);
  });

  testWidgets('summaryFor captions a section from every control under it, subsections included', (
    tester,
  ) async {
    await _pump(
      tester,
      nested,
      summaryFor: (c) => '${c.where((x) => x.status != 'Pending').length}/${c.length}',
    );

    expect(find.text('1/2'), findsOneWidget); // Impianto: a + b, b done
    expect(find.text('1/1'), findsOneWidget); // Quadro: b
  });
}
