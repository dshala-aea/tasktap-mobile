// test/golden/redesign/list_shell_cantieri_demo_test.dart
//
// Review artifact for Task 0b: the shared list shell rendered with the Cantieri entry from
// `prototypes/list-screens.html`. Writes `build/redesign/list_shell_cantieri.png`; nothing here
// compares images, so the test passes in CI.
//
// Run:
//   fvm flutter test test/golden/redesign/list_shell_cantieri_demo_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/list/list_shell.dart';
import 'package:tasktap_mobile/core/widgets/list/list_models.dart';

import 'redesign_harness.dart';

void main() {
  setUpAll(loadRedesignFonts);

  testWidgets('list shell with the Cantieri prototype data', (tester) async {
    await captureRedesign(
      tester,
      'list_shell_cantieri',
      child: const ListShell(
        title: 'Cantieri',
        subtitle:
            'Cosa devo seguire oggi, e quali cantieri sono ancora attivi.',
        action: ListHeaderAction(label: 'Nuovo', onPressed: _noop),
        searchHint: 'Cerca cantiere, cliente, indirizzo o codice…',
        filters: [
          ListFilterChipData(label: 'Attivi'),
          ListFilterChipData(label: 'Tutti'),
          ListFilterChipData(label: 'Pianificati'),
          ListFilterChipData(label: 'Chiusi'),
        ],
        activeFilterIndex: 0,
        onOpenFilters: _noop,
        groups: [
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
            title: 'Altri cantieri attivi',
            count: 2,
            rows: [
              ListRowData(
                title: 'Cantiere Nord',
                meta: 'Verdi Spa · Sesto · 4 operatori',
                secondary: 'Nessuna attività oggi · prossima domani 08:00',
                status: 'Attivo',
                statusTone: ListStatusTone.good,
              ),
              ListRowData(
                title: 'Pulizia impianti',
                meta: 'Gialli Srl · Monza · 2 operatori',
                secondary: 'Ultima attività · 12/11',
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
        ],
        summary: ListSummaryData(left: '8 cantieri attivi', right: '2 oggi'),
      ),
    );
  });
}

void _noop() {}
