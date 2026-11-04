import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/core/widgets/app_tappable.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_hero.dart';

void _noop() {}

void main() {
  testWidgets('renders entity title, subtitle, stamp and three facts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DetailHero(
          data: DetailHeroData(
            variant: DetailHeroVariant.operational,
            title: 'Perdita acqua sotto il lavello',
            subtitle: 'INT-2026-0412',
            status: const DetailStatus(
              label: 'In corso',
              tone: DetailStatusTone.warn,
            ),
            facts: const [
              DetailFact(label: 'Cliente', value: 'Rossi Srl'),
              DetailFact(label: 'Sede', value: 'Milano'),
              DetailFact(label: 'Tecnico', value: 'D. Shala'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Perdita acqua sotto il lavello'), findsOneWidget);
    expect(find.text('INT-2026-0412'), findsOneWidget);
    expect(find.text('IN CORSO'), findsOneWidget);
    expect(find.text('Rossi Srl'), findsOneWidget);
  });

  testWidgets('renders at most three facts and accepts a const data literal', (
    tester,
  ) async {
    const data = DetailHeroData(
      variant: DetailHeroVariant.summary,
      title: 'Cliente',
      status: DetailStatus(label: 'Attivo'),
      facts: [
        DetailFact(label: 'A', value: '1'),
        DetailFact(label: 'B', value: '2'),
        DetailFact(label: 'C', value: '3'),
        DetailFact(label: 'D', value: '4'),
      ],
    );

    await tester.pumpWidget(MaterialApp(home: DetailHero(data: data)));

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsNothing);
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
                facts: const [
                  DetailFact(label: 'Cliente', value: 'Rossi Srl'),
                  DetailFact(label: 'Sede', value: 'Milano'),
                  DetailFact(label: 'Tecnico', value: 'D. Shala'),
                ],
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

  testWidgets('actions and tappable facts meet the 48px touch target', (
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
              facts: const [
                DetailFact(label: 'Cliente', value: 'Rossi Srl', onTap: _noop),
              ],
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

    final buttons = find.byType(AppButton);
    expect(buttons, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      expect(tester.getSize(buttons.at(i)).height, greaterThanOrEqualTo(48));
    }
    expect(
      tester.getSize(find.byType(AppTappable)).height,
      greaterThanOrEqualTo(48),
    );
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
