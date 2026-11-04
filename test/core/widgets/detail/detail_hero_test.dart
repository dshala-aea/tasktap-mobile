import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/detail/detail_hero.dart';

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

  testWidgets('more than three facts are rejected', (tester) async {
    expect(
      () => DetailHeroData(
        variant: DetailHeroVariant.summary,
        title: 'Cliente',
        status: const DetailStatus(label: 'Attivo'),
        facts: const [
          DetailFact(label: 'A', value: '1'),
          DetailFact(label: 'B', value: '2'),
          DetailFact(label: 'C', value: '3'),
          DetailFact(label: 'D', value: '4'),
        ],
      ),
      throwsAssertionError,
    );
  });

  testWidgets('long titles clamp to two lines without overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          child: DetailHero(
            data: DetailHeroData(
              variant: DetailHeroVariant.operational,
              title:
                  'Perdita acqua sotto il lavello della cucina del piano primo con allagamento',
              status: const DetailStatus(label: 'In corso'),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Perdita acqua sotto'), findsOneWidget);
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
