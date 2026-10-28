import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/data/badge/badge_api_client.dart';
import 'package:tasktap_mobile/data/badge/badge_models.dart';
import 'package:tasktap_mobile/features/badge/badge_scan_controller.dart';
import 'package:tasktap_mobile/features/badge/badge_scan_result_card.dart';

final _at = DateTime.utc(2026, 10, 28, 8);

BadgeScanEntry _o(BadgeScanResult r, [BadgeScanAction a = BadgeScanAction.none, BadgeWorker? w]) =>
    BadgeScanEntry.outcome(_at, BadgeScanOutcome(result: r, action: a, worker: w));

Future<void> _pump(WidgetTester t, BadgeScanEntry e) => t.pumpWidget(
  MaterialApp(
    home: Scaffold(body: BadgeScanResultCard(entry: e)),
  ),
);

void main() {
  const texts = <BadgeScanResult, String>{
    BadgeScanResult.notAssigned: 'Non assegnato a questo cantiere — segnalato all\'ufficio',
    BadgeScanResult.revoked: 'Badge non valido — contatta l\'ufficio',
    BadgeScanResult.expired: 'Badge scaduto — chiedi di riaprire il badge',
    BadgeScanResult.replayed: 'Codice già usato — se il lavoratore risulta già registrato non serve altro, altrimenti chiedi di aggiornare il badge',
    BadgeScanResult.invalid: 'Codice non riconosciuto',
    BadgeScanResult.openElsewhere: 'Ha un turno aperto su un altro cantiere',
    BadgeScanResult.payrollLocked: 'Periodo paghe chiuso — contatta l\'ufficio',
    BadgeScanResult.unknown: 'Risposta non riconosciuta — riprova',
  };

  // A theory over EVERY BadgeScanResult: a new enum member fails here until it is mapped.
  for (final r in BadgeScanResult.values) {
    if (r == BadgeScanResult.accepted) continue;
    testWidgets('non-success $r renders its text, an icon and never the success style', (t) async {
      expect(texts.containsKey(r), isTrue, reason: '$r has no expected text in this test');
      await _pump(t, _o(r));
      expect(find.text(texts[r]!), findsOneWidget);
      expect(find.byKey(const ValueKey('badge-scan-card-success')), findsNothing);
      final icon = t.widget<Icon>(find.byType(Icon));
      expect(icon.icon, isNot(LucideIcons.check));
    });
  }

  for (final (a, text) in [
    (BadgeScanAction.opened, 'ENTRATA registrata'),
    (BadgeScanAction.closed, 'USCITA registrata'),
    (BadgeScanAction.none, 'Già registrato'),
  ]) {
    testWidgets('accepted + $a shows "$text" with the success style and a check', (t) async {
      await _pump(t, _o(BadgeScanResult.accepted, a));
      expect(find.text(text), findsOneWidget);
      expect(find.byKey(const ValueKey('badge-scan-card-success')), findsOneWidget);
      expect(t.widget<Icon>(find.byType(Icon)).icon, LucideIcons.check);
    });
  }

  testWidgets('unknown_result_never_renders_as_success', (t) async {
    await _pump(t, _o(BadgeScanResult.unknown, BadgeScanAction.opened));
    expect(find.text('Risposta non riconosciuta — riprova'), findsOneWidget);
    expect(find.byKey(const ValueKey('badge-scan-card-success')), findsNothing);
    // Accepted with an action this build cannot name is not claimed as a success either.
    await _pump(t, _o(BadgeScanResult.accepted, BadgeScanAction.unknown));
    expect(find.text('Risposta non riconosciuta — riprova'), findsOneWidget);
    expect(find.byKey(const ValueKey('badge-scan-card-success')), findsNothing);
  });

  testWidgets('shows worker name when worker != null and initials without a photo', (t) async {
    await _pump(
      t,
      _o(
        BadgeScanResult.accepted,
        BadgeScanAction.opened,
        const BadgeWorker(displayName: 'Mario Rossi', employerName: 'Bianchi Srl'),
      ),
    );
    expect(find.text('Mario Rossi'), findsOneWidget);
    expect(find.text('MR'), findsOneWidget);
  });

  testWidgets('notlead_403_shows_message', (t) async {
    await _pump(
      t,
      BadgeScanEntry.failure(
        _at,
        BadgeApiException(statusCode: 403, code: 'NotLead', message: 'x'),
      ),
    );
    expect(find.text('Solo il capo squadra può scansionare'), findsOneWidget);
  });

  testWidgets('offline_shows_message_and_allows_retry', (t) async {
    await _pump(t, BadgeScanEntry.failure(_at, const BadgeApiException(message: 'n', offline: true)));
    expect(find.text('Nessuna connessione — riprova'), findsOneWidget);
    expect(t.widget<Icon>(find.byType(Icon)).icon, LucideIcons.wifiOff);
  });

  for (final code in [502, 503, 504]) {
    testWidgets('gateway $code reads as no connection', (t) async {
      await _pump(t, BadgeScanEntry.failure(_at, BadgeApiException(statusCode: code, message: 'g')));
      expect(find.text('Nessuna connessione — riprova'), findsOneWidget);
    });
  }

  testWidgets('a 500 and an unexpected error render a generic non-success entry', (t) async {
    await _pump(t, BadgeScanEntry.failure(_at, const BadgeApiException(statusCode: 500, message: 's')));
    expect(find.text('Scansione non riuscita — riprova'), findsOneWidget);
    await _pump(t, BadgeScanEntry.unexpected(_at, 'StateError'));
    expect(find.text('Scansione non riuscita — riprova'), findsOneWidget);
    expect(find.byKey(const ValueKey('badge-scan-card-success')), findsNothing);
  });
}
