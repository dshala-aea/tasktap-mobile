import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/theme/status_colors.dart';
import 'package:tasktap_mobile/core/widgets/list/list_document_row.dart';
import 'package:tasktap_mobile/core/widgets/list/list_models.dart';
import 'package:tasktap_mobile/core/widgets/status_stamp.dart';

Widget _app(Widget child) => MaterialApp(
  theme: buildAppTheme(brightness: Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  group('ListDocumentRow', () {
    testWidgets('renders title, meta, secondary and a text-carrying stamp', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ListDocumentRow(
            data: ListRowData(
              title: 'Ristrutturazione Via Roma',
              meta: 'Rossi Srl · Milano · 3 operatori',
              secondary: 'In corso · 08:30–12:30',
              status: 'Attivo',
              statusTone: ListStatusTone.good,
            ),
          ),
        ),
      );

      expect(find.text('Ristrutturazione Via Roma'), findsOneWidget);
      expect(find.text('Rossi Srl · Milano · 3 operatori'), findsOneWidget);
      expect(find.text('In corso · 08:30–12:30'), findsOneWidget);
      expect(find.text('ATTIVO'), findsOneWidget);

      final stamp = tester.widget<StatusStamp>(find.byType(StatusStamp));
      expect(stamp.family, StatusFamily.good);
    });

    testWidgets('a tone override wins over the status string mapping', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ListDocumentRow(
            data: ListRowData(
              title: 'Sostituzione infissi',
              status: 'Pianificato',
              statusTone: ListStatusTone.info,
            ),
          ),
        ),
      );

      final stamp = tester.widget<StatusStamp>(find.byType(StatusStamp));
      expect(stamp.family, StatusFamily.info);
    });

    testWidgets('only tappable rows show the chevron and fire on tap', (
      tester,
    ) async {
      var tapped = false;

      await tester.pumpWidget(
        _app(const ListDocumentRow(data: ListRowData(title: 'Non tappabile'))),
      );
      expect(find.byIcon(LucideIcons.chevronRight), findsNothing);

      await tester.pumpWidget(
        _app(
          ListDocumentRow(
            data: ListRowData(title: 'Tappabile', onTap: () => tapped = true),
          ),
        ),
      );
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);

      await tester.tap(find.text('Tappabile'));
      expect(tapped, isTrue);
    });

    testWidgets('the row is at least a 44px target', (tester) async {
      await tester.pumpWidget(
        _app(const ListDocumentRow(data: ListRowData(title: 'Riga'))),
      );

      expect(
        tester.getSize(find.byType(ListDocumentRow)).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('a leading slot renders before the text column', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const ListDocumentRow(
            data: ListRowData(title: 'Con icona', leading: Icon(Icons.build)),
          ),
        ),
      );

      expect(find.byIcon(Icons.build), findsOneWidget);
      expect(
        tester.getTopLeft(find.byIcon(Icons.build)).dx,
        lessThan(tester.getTopLeft(find.text('Con icona')).dx),
      );
    });
  });
}
