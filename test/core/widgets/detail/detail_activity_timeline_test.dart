import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_activity_timeline.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_attachment_row.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_section.dart';

void main() {
  testWidgets(
    'renders time, title and meta per event, in order, with a vertical rule',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DetailActivityTimeline(
              events: [
                DetailActivityEvent(
                  time: '09:12',
                  title: 'Ingresso in cantiere',
                  meta: 'Posizione registrata',
                  tone: DetailEventTone.good,
                ),
                DetailActivityEvent(time: '09:20', title: 'Nota aggiunta'),
                DetailActivityEvent(
                  time: '09:34',
                  title: 'Materiale registrato',
                  tone: DetailEventTone.warn,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('09:12'), findsOneWidget);
      expect(find.text('Posizione registrata'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Nota aggiunta')).dy,
        lessThan(tester.getTopLeft(find.text('Materiale registrato')).dy),
      );
      final time = tester.widget<Text>(find.text('09:12'));
      expect(time.style!.fontFamily, 'IBM Plex Mono');
      expect(time.style!.fontSize, 8.5);
      final title = tester.widget<Text>(find.text('Ingresso in cantiere'));
      expect(title.style!.fontSize, 11.5);
      expect(title.style!.fontWeight, FontWeight.w600);
      // Title is indented past the 22px dot gutter.
      expect(
        tester.getTopLeft(find.text('Nota aggiunta')).dx,
        greaterThanOrEqualTo(22),
      );
    },
  );

  testWidgets('dots are 9px: outline when neutral, filled by tone otherwise', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DetailActivityTimeline(
            events: [
              DetailActivityEvent(time: '1', title: 'neutral'),
              DetailActivityEvent(
                time: '2',
                title: 'good',
                tone: DetailEventTone.good,
              ),
            ],
          ),
        ),
      ),
    );
    final colors = AppPalette.light;
    final dots = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.constraints?.maxWidth == 9)
        .map((c) => c.decoration! as BoxDecoration)
        .toList();
    expect(dots, hasLength(2));
    expect(dots[0].color, colors.surface);
    expect(dots[0].border!.top.color, colors.inkMuted);
    expect(dots[1].color, colors.green);
    expect(dots[1].border!.top.color, colors.green);
  });

  testWidgets('an empty timeline renders nothing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DetailActivityTimeline(events: [])),
      ),
    );
    expect(find.byKey(const Key('detail-activity-timeline')), findsNothing);
  });

  testWidgets(
    'section header: Archivo Narrow 17/600 title, uppercase mono trailing',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DetailSection(
              data: DetailSectionData(
                title: 'Sintesi',
                trailing: DetailSectionMeta('4 campi'),
                child: SizedBox(),
              ),
            ),
          ),
        ),
      );
      final title = tester.widget<Text>(find.text('Sintesi'));
      expect(title.style!.fontFamily, 'Archivo Narrow');
      expect(title.style!.fontSize, 17);
      expect(title.style!.fontWeight, FontWeight.w600);
      expect(find.text('4 CAMPI'), findsOneWidget);
      final trailing = tester.widget<DefaultTextStyle>(
        find
            .ancestor(
              of: find.text('4 CAMPI'),
              matching: find.byType(DefaultTextStyle),
            )
            .first,
      );
      expect(trailing.style.fontSize, 9);
      expect(trailing.style.fontFamily, 'IBM Plex Mono');
    },
  );

  testWidgets('section link fires and shows uppercase', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailSection(
            data: DetailSectionData(
              title: 'Attività',
              trailing: DetailSectionLink(label: 'Apri', onTap: () => taps++),
              child: const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('APRI'));
    expect(taps, 1);
  });

  testWidgets('attachment row: name, mono size, 28px icon box, rules', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              DetailAttachmentRow(
                name: 'foto_lavello.jpg',
                icon: const Icon(Icons.attach_file),
                size: '2,4 MB',
                onTap: () => taps++,
              ),
              const DetailAttachmentRow(
                name: 'firma_cliente.png',
                icon: Icon(Icons.attach_file),
                size: '96 KB',
                isLast: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('2,4 MB'), findsOneWidget);
    final name = tester.widget<Text>(find.text('foto_lavello.jpg'));
    expect(name.style!.fontSize, 11);
    expect(name.maxLines, 1);
    expect(
      tester.widget<Text>(find.text('96 KB')).style!.fontFamily,
      'IBM Plex Mono',
    );
    await tester.tap(find.text('foto_lavello.jpg'));
    expect(taps, 1);
  });
}
