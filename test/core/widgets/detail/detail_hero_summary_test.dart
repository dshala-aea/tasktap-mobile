import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_hero.dart';
import 'package:tasktap_mobile/core/widgets/status_stamp.dart';

void _noop() {}

void main() {
  group('DetailHero summary variant', () {
    testWidgets(
      'puts the entity title and facts inside the hero card, with a stamp',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: Brightness.light),
            home: const Scaffold(
              body: DetailHero(
                data: DetailHeroData(
                  variant: DetailHeroVariant.summary,
                  kind: 'Summary · cliente',
                  title: 'Rossi Srl',
                  subtitle: 'Milano · 12 sedi · 4 contratti',
                  status: DetailStatus(
                    label: 'Attivo',
                    tone: DetailStatusTone.good,
                  ),
                  primaryAction: DetailAction(
                    label: 'Modifica',
                    onPressed: _noop,
                  ),
                ),
              ),
            ),
          ),
        );

        final card = find.byKey(const Key('detail-hero-card'));
        expect(
          find.descendant(
            of: card,
            matching: find.byKey(const Key('detail-hero-title')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.byKey(const Key('detail-hero-subtitle')),
          ),
          findsOneWidget,
        );
        expect(find.text('SUMMARY · CLIENTE'), findsOneWidget);
        expect(find.byType(StatusStamp), findsOneWidget);
        expect(find.text('ATTIVO'), findsOneWidget);
        expect(find.text('Modifica'), findsOneWidget);
      },
    );

    testWidgets(
      'uses Apri PDF as the primary action when the caller supplies it',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: Brightness.light),
            home: const Scaffold(
              body: DetailHero(
                data: DetailHeroData(
                  variant: DetailHeroVariant.summary,
                  title: 'Rapportino 2026-0412',
                  status: DetailStatus(label: 'Inviato'),
                  primaryAction: DetailAction(
                    label: 'Apri PDF',
                    onPressed: _noop,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('Apri PDF'), findsOneWidget);
      },
    );

    testWidgets('summary variant ignores a live value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.light),
          home: const Scaffold(
            body: DetailHero(
              data: DetailHeroData(
                variant: DetailHeroVariant.summary,
                title: 'Magazzino Milano',
                status: DetailStatus(label: '6 sotto scorta'),
                liveValue: Text('00:42:18'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('00:42:18'), findsNothing);
    });
  });
}
