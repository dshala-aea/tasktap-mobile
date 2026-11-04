import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_hero.dart';

void _noop() {}

void main() {
  testWidgets(
    'title, kicker and subtitle sit above the card; the card holds state and actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DetailHero(
                data: DetailHeroData(
                  variant: DetailHeroVariant.operational,
                  title: 'Perdita acqua sotto il lavello',
                  kicker: 'Ticket · INT-2026-0412',
                  kickerContext: 'Oggi',
                  subtitle: 'Rossi Srl · Sede Milano\nAssegnato a Daniel Shala',
                  status: const DetailStatus(
                    label: 'In corso',
                    tone: DetailStatusTone.warn,
                  ),
                  heroCopy: const Text('Ingresso alle 09:12'),
                  liveValue: const Text('00:42:18'),
                  primaryAction: const DetailAction(
                    label: 'Timbra uscita',
                    onPressed: _noop,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('PERDITA ACQUA SOTTO IL LAVELLO'), findsNothing);
      expect(find.text('Perdita acqua sotto il lavello'), findsOneWidget);
      expect(find.text('TICKET · INT-2026-0412'), findsOneWidget);
      expect(find.text('OGGI'), findsOneWidget);
      expect(find.text('IN CORSO'), findsOneWidget);

      final card = find.byKey(const Key('detail-hero-card'));
      // Title, kicker and subtitle are outside the card; state, timer, copy and action inside it.
      for (final outside in [
        find.byKey(const Key('detail-hero-title')),
        find.byKey(const Key('detail-hero-kicker')),
        find.byKey(const Key('detail-hero-subtitle')),
      ]) {
        expect(find.descendant(of: card, matching: outside), findsNothing);
        expect(
          tester.getBottomLeft(outside).dy,
          lessThanOrEqualTo(tester.getTopLeft(card).dy),
        );
      }
      for (final inside in [
        'IN CORSO',
        '00:42:18',
        'Ingresso alle 09:12',
        'Timbra uscita',
      ]) {
        expect(
          find.descendant(of: card, matching: find.text(inside)),
          findsOneWidget,
        );
      }
      // Kicker above title above subtitle.
      final kickerY = tester
          .getTopLeft(find.byKey(const Key('detail-hero-kicker')))
          .dy;
      final titleY = tester
          .getTopLeft(find.byKey(const Key('detail-hero-title')))
          .dy;
      final subY = tester
          .getTopLeft(find.byKey(const Key('detail-hero-subtitle')))
          .dy;
      expect(kickerY, lessThan(titleY));
      expect(titleY, lessThan(subY));

      final title = tester.widget<Text>(
        find.byKey(const Key('detail-hero-title')),
      );
      expect(title.maxLines, 2);
      expect(title.style!.fontSize, 30);
      expect(title.style!.height, 0.98);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('detail-hero-subtitle')))
            .maxLines,
        2,
      );
    },
  );

  testWidgets('hero without kicker or subtitle renders just title and card', (
    tester,
  ) async {
    const data = DetailHeroData(
      variant: DetailHeroVariant.summary,
      title: 'Cliente',
      status: DetailStatus(label: 'Attivo'),
    );

    await tester.pumpWidget(const MaterialApp(home: DetailHero(data: data)));

    expect(find.byKey(const Key('detail-hero-kicker')), findsNothing);
    expect(find.byKey(const Key('detail-hero-subtitle')), findsNothing);
    expect(find.text('Cliente'), findsOneWidget);
    expect(find.text('ATTIVO'), findsOneWidget);
  });

  testWidgets(
    'long titles and actions fit a 320px viewport without overflowing',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetailHero(
              data: DetailHeroData(
                variant: DetailHeroVariant.operational,
                title:
                    'Perdita acqua sotto il lavello della cucina del piano primo con allagamento',
                status: const DetailStatus(label: 'In corso'),
                primaryAction: const DetailAction(
                  label: 'Avvia intervento',
                  onPressed: _noop,
                ),
                secondaryActions: const [
                  DetailAction(label: 'AI Copilot', onPressed: _noop),
                  DetailAction(label: 'Crea rapportino', onPressed: _noop),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(DetailHero)).width, 320);
      expect(find.textContaining('Perdita acqua sotto'), findsOneWidget);
      expect(find.text('Avvia intervento'), findsOneWidget);
      expect(find.text('AI Copilot'), findsOneWidget);
      expect(find.text('Crea rapportino'), findsOneWidget);
    },
  );

  testWidgets('primary action is a 48px target, row actions at least 44px', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailHero(
            data: DetailHeroData(
              variant: DetailHeroVariant.operational,
              title: 'Ticket',
              status: const DetailStatus(label: 'Aperto'),
              primaryAction: const DetailAction(
                label: 'Avvia intervento',
                onPressed: _noop,
              ),
              secondaryActions: const [
                DetailAction(label: 'AI Copilot', onPressed: _noop),
                DetailAction(label: 'Crea rapportino', onPressed: _noop),
              ],
            ),
          ),
        ),
      ),
    );

    final buttons = find.byType(DetailHeroButton);
    expect(buttons, findsNWidgets(3));
    expect(tester.getSize(buttons.at(0)).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(buttons.at(1)).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(buttons.at(2)).height, greaterThanOrEqualTo(44));
  });

  testWidgets('disabled primary action shows its reason and never fires', (
    tester,
  ) async {
    var fired = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DetailHero(
          data: DetailHeroData(
            variant: DetailHeroVariant.operational,
            title: 'Ticket',
            status: const DetailStatus(label: 'Aperto'),
            primaryAction: DetailAction(
              label: 'Avvia intervento',
              enabled: false,
              disabledReason: 'Timer non disponibile offline',
              onPressed: () => fired = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Timer non disponibile offline'), findsOneWidget);
    await tester.tap(find.text('Avvia intervento'));
    expect(fired, isFalse);
  });

  testWidgets('enabled primary action fires', (tester) async {
    var fired = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DetailHero(
          data: DetailHeroData(
            variant: DetailHeroVariant.operational,
            title: 'Ticket',
            status: const DetailStatus(label: 'Aperto'),
            primaryAction: DetailAction(
              label: 'Avvia intervento',
              onPressed: () => fired = true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Avvia intervento'));
    expect(fired, isTrue);
  });

  testWidgets('operational hero shows the live value, summary hero does not', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DetailHero(
          data: DetailHeroData(
            variant: DetailHeroVariant.operational,
            title: 'Ticket',
            status: const DetailStatus(label: 'In corso'),
            liveValue: const Text('00:12:34'),
          ),
        ),
      ),
    );
    expect(find.text('00:12:34'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: DetailHero(
          data: DetailHeroData(
            variant: DetailHeroVariant.summary,
            title: 'Cliente',
            status: const DetailStatus(label: 'Attivo'),
            liveValue: const Text('00:12:34'),
          ),
        ),
      ),
    );
    expect(find.text('00:12:34'), findsNothing);
  });
}
