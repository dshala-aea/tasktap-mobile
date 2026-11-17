import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/list/list_group_header.dart';
import 'package:tasktap_mobile/core/widgets/list/list_shell.dart';
import 'package:tasktap_mobile/core/widgets/list/list_models.dart';
import 'package:tasktap_mobile/core/widgets/unavailable_state.dart';

const _groups = [
  ListGroupData(
    title: 'Da seguire oggi',
    count: 2,
    rows: [
      ListRowData(
        title: 'Ristrutturazione Via Roma',
        meta: 'Rossi Srl · Milano · 3 operatori',
        secondary: 'In corso · 08:30–12:30',
        status: 'Attivo',
        statusTone: ListStatusTone.good,
      ),
      ListRowData(
        title: 'Manutenzione caldaie',
        meta: 'Bianchi Srl · Milano · 2 operatori',
        secondary: 'Timbrato oggi · 09:00–11:30',
        status: 'Attivo',
        statusTone: ListStatusTone.good,
      ),
    ],
  ),
  ListGroupData(
    title: 'Pianificati',
    count: 1,
    rows: [
      ListRowData(
        title: 'Sostituzione infissi',
        meta: 'Neri Srl · Milano',
        secondary: 'Inizio · 18/11',
        status: 'Pianificato',
        statusTone: ListStatusTone.info,
      ),
    ],
  ),
];

Widget _app(Widget child) => MaterialApp(
  theme: buildAppTheme(brightness: Brightness.light),
  home: child,
);

void main() {
  group('ListShell', () {
    testWidgets(
      'renders header, search, chips, groups, rows and summary in order',
      (tester) async {
        await tester.pumpWidget(
          _app(
            const ListShell(
              title: 'Cantieri',
              subtitle:
                  'Cosa devo seguire oggi, e quali cantieri sono ancora attivi.',
              action: ListHeaderAction(label: 'Nuovo', onPressed: _noop),
              searchHint: 'Cerca cantiere, cliente, indirizzo o codice…',
              filters: [
                ListFilterChipData(label: 'Attivi'),
                ListFilterChipData(label: 'Tutti'),
              ],
              activeFilterIndex: 0,
              groups: _groups,
              summary: ListSummaryData(
                left: '8 cantieri attivi',
                right: '2 oggi',
              ),
            ),
          ),
        );

        expect(find.text('Cantieri'), findsOneWidget);
        expect(
          find.text(
            'Cosa devo seguire oggi, e quali cantieri sono ancora attivi.',
          ),
          findsOneWidget,
        );
        expect(find.text('NUOVO'), findsOneWidget);
        expect(
          find.text('Cerca cantiere, cliente, indirizzo o codice…'),
          findsOneWidget,
        );
        expect(find.text('ATTIVI'), findsOneWidget);
        expect(find.text('TUTTI'), findsOneWidget);
        expect(find.text('Da seguire oggi'), findsOneWidget);
        expect(find.text('Ristrutturazione Via Roma'), findsOneWidget);
        expect(find.text('Pianificati'), findsOneWidget);
        expect(find.text('8 CANTIERI ATTIVI'), findsOneWidget);
        expect(find.text('2 OGGI'), findsOneWidget);

        final titleY = tester.getTopLeft(find.text('Cantieri')).dy;
        final searchY = tester
            .getTopLeft(find.textContaining('Cerca cantiere'))
            .dy;
        final chipY = tester.getTopLeft(find.text('ATTIVI')).dy;
        final groupY = tester.getTopLeft(find.text('Da seguire oggi')).dy;
        final rowY = tester
            .getTopLeft(find.text('Ristrutturazione Via Roma'))
            .dy;
        final summaryY = tester.getTopLeft(find.text('8 CANTIERI ATTIVI')).dy;

        expect(titleY, lessThan(searchY));
        expect(searchY, lessThan(chipY));
        expect(chipY, lessThan(groupY));
        expect(groupY, lessThan(rowY));
        expect(rowY, lessThan(summaryY));
      },
    );

    testWidgets('omitting the action hides the write control', (tester) async {
      await tester.pumpWidget(
        _app(const ListShell(title: 'Report admin', groups: _groups)),
      );
      expect(find.text('NUOVO'), findsNothing);
    });

    testWidgets('filter chips and the red Filtri chip call their callbacks', (
      tester,
    ) async {
      ListFilterChipData? selected;
      var opened = false;

      await tester.pumpWidget(
        _app(
          ListShell(
            title: 'Cantieri',
            filters: const [
              ListFilterChipData(label: 'Attivi', id: 'active'),
              ListFilterChipData(label: 'Tutti', id: 'all'),
            ],
            activeFilterId: 'active',
            onFilterSelected: (chip) => selected = chip,
            onOpenFilters: () => opened = true,
            groups: _groups,
          ),
        ),
      );

      await tester.tap(find.text('TUTTI'));
      expect(selected?.id, 'all');

      await tester.tap(find.text('FILTRI'));
      expect(opened, isTrue);
    });

    testWidgets('loading state shows the skeleton, not rows', (tester) async {
      await tester.pumpWidget(
        _app(
          const ListShell(
            title: 'Cantieri',
            state: ListShellState.loading,
            groups: _groups,
          ),
        ),
      );

      expect(find.byKey(const Key('list-loading-skeleton')), findsOneWidget);
      expect(find.text('Ristrutturazione Via Roma'), findsNothing);
    });

    testWidgets('unavailable state shows the supplied retry state', (
      tester,
    ) async {
      var retried = false;

      await tester.pumpWidget(
        _app(
          ListShell(
            title: 'Cantieri',
            state: ListShellState.unavailable,
            unavailable: UnavailableState(
              titolo: 'Cantieri non disponibili',
              motivo:
                  'Questo telefono non ha ancora completato una sincronizzazione.',
              action: TextButton(
                onPressed: () => retried = true,
                child: const Text('Riprova'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Cantieri non disponibili'), findsOneWidget);
      await tester.tap(find.text('Riprova'));
      expect(retried, isTrue);
    });

    testWidgets('empty content shows the generic filter-empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const ListShell(title: 'Cantieri', groups: [])),
      );

      expect(find.text('Nessun risultato'), findsOneWidget);
    });

    testWidgets('a caller-supplied empty state replaces the generic one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ListShell(
            title: 'Cantieri',
            groups: [],
            empty: Text('Catalogo non ancora scaricato'),
          ),
        ),
      );

      expect(find.text('Catalogo non ancora scaricato'), findsOneWidget);
      expect(find.text('Nessun risultato'), findsNothing);
    });

    testWidgets('the banner slot sits above the header', (tester) async {
      await tester.pumpWidget(
        _app(
          const ListShell(
            title: 'Cantieri',
            banner: Text('Offline · 2 in coda'),
            groups: _groups,
          ),
        ),
      );

      expect(find.text('Offline · 2 in coda'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Offline · 2 in coda')).dy,
        lessThan(tester.getTopLeft(find.text('Cantieri')).dy),
      );
    });

    testWidgets(
      'a group without a title renders a flat list with no header or rule',
      (tester) async {
        await tester.pumpWidget(
          _app(
            const ListShell(
              title: 'Ferie',
              groups: [
                ListGroupData(
                  rows: [
                    ListRowData(
                      title: 'Daniel Shala',
                      meta: 'Ferie · 18–22/11',
                      secondary: '3 giorni · in attesa',
                      status: 'In attesa',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        expect(find.byType(ListGroupHeader), findsNothing);
        expect(find.text('Daniel Shala'), findsOneWidget);
        expect(find.text('IN ATTESA'), findsOneWidget);
      },
    );

    testWidgets('long Italian strings clamp without overflowing at 320px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app(
          const ListShell(
            title: 'Cantieri',
            groups: [
              ListGroupData(
                title: 'Da seguire oggi',
                count: 1,
                rows: [
                  ListRowData(
                    title:
                        'Ristrutturazione straordinaria del piano primo con rifacimento completo degli impianti',
                    meta:
                        'Rossi Costruzioni e Impianti Srl · Milano · Via Roma 1 · tre operatori assegnati',
                    secondary:
                        'In corso dalle 08:30 alle 12:30 · prossima attività domani mattina alle 08:00',
                    status: 'In corso',
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(
        find.textContaining('Ristrutturazione straordinaria'),
      );
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);

      final meta = tester.widget<Text>(
        find.textContaining('Rossi Costruzioni'),
      );
      expect(meta.maxLines, 1);
      expect(meta.overflow, TextOverflow.ellipsis);
    });
  });
}

void _noop() {}
