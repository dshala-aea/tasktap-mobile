import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/scanner/continuous_scan_view.dart';
import 'package:tasktap_mobile/data/badge/badge_api_client.dart';
import 'package:tasktap_mobile/data/badge/badge_models.dart';
import 'package:tasktap_mobile/features/badge/badge_providers.dart';
import 'package:tasktap_mobile/features/badge/badge_scan_controller.dart';
import 'package:tasktap_mobile/features/badge/badge_scan_screen.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_providers.dart';

class _FakeApi implements BadgeApiClient {
  final Map<String, Object> byToken;
  _FakeApi(this.byToken);

  @override
  Future<BadgeScanOutcome> scan({
    required String cantiereId,
    required String token,
    required String clientScanId,
  }) async {
    final r = byToken[token]!;
    if (r is BadgeScanOutcome) return r;
    throw r;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BadgeScanOutcome _ok(String name, BadgeScanAction a) => BadgeScanOutcome(
  result: BadgeScanResult.accepted,
  action: a,
  worker: BadgeWorker(displayName: name, employerName: 'Bianchi Srl'),
);

void main() {
  late void Function(String) emit;
  late DateTime now;

  Widget app(_FakeApi api) => ProviderScope(
    overrides: [
      badgeApiClientProvider.overrideWithValue(api),
      badgeScanClockProvider.overrideWithValue(() => now),
      cantiereByIdProvider.overrideWith((ref, id) => const Stream.empty()),
    ],
    child: MaterialApp(
      home: BadgeScanScreen(
        cantiereId: 'c1',
        scanSource: (context, onCode) {
          emit = onCode;
          return const SizedBox.expand(key: ValueKey('fake-camera'));
        },
      ),
    ),
  );

  setUp(() => now = DateTime.utc(2026, 10, 28, 8));

  testWidgets('lists scanned workers newest first with the camera still on screen', (t) async {
    await t.pumpWidget(
      app(
        _FakeApi({
          'a': _ok('Mario Rossi', BadgeScanAction.opened),
          'b': _ok('Luca Verdi', BadgeScanAction.closed),
        }),
      ),
    );
    expect(find.text('Inquadra il badge del lavoratore'), findsOneWidget);

    emit('a');
    await t.pumpAndSettle();
    now = now.add(const Duration(seconds: 1));
    emit('b');
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('fake-camera')), findsOneWidget);
    final luca = t.getTopLeft(find.text('Luca Verdi')).dy;
    final mario = t.getTopLeft(find.text('Mario Rossi')).dy;
    expect(luca, lessThan(mario), reason: 'newest first');
    expect(find.text('USCITA registrata'), findsOneWidget);
    expect(find.text('ENTRATA registrata'), findsOneWidget);
  });

  testWidgets('the newest result is a live region; a failed scan never shows success', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      app(_FakeApi({'a': const BadgeApiException(statusCode: 403, code: 'NotLead', message: 'x')})),
    );
    emit('a');
    await t.pumpAndSettle();
    expect(find.text('Solo il capo squadra può scansionare'), findsOneWidget);
    expect(find.byKey(const ValueKey('badge-scan-card-success')), findsNothing);
    expect(
      t.getSemantics(find.bySemanticsLabel('Solo il capo squadra può scansionare')),
      isSemantics(isLiveRegion: true),
    );
    handle.dispose();
  });

  testWidgets('offline: shown, and the same badge can be retried after the window', (t) async {
    await t.pumpWidget(app(_FakeApi({'a': const BadgeApiException(message: 'n', offline: true)})));
    emit('a');
    await t.pumpAndSettle();
    expect(find.text('Nessuna connessione — riprova'), findsOneWidget);
    now = now.add(badgeScanDedupeWindow);
    emit('a');
    await t.pumpAndSettle();
    expect(find.text('Nessuna connessione — riprova'), findsNWidgets(2));
  });

  testWidgets('keeps the screen awake while scanning and releases it on leave', (t) async {
    final wake = _FakeWakelock();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          badgeWakelockProvider.overrideWithValue(wake),
          badgeApiClientProvider.overrideWithValue(_FakeApi(const {})),
          cantiereByIdProvider.overrideWith((ref, id) => const Stream.empty()),
        ],
        child: MaterialApp(
          home: BadgeScanScreen(cantiereId: 'c1', scanSource: (_, _) => const SizedBox()),
        ),
      ),
    );
    expect(wake.enables, 1);
    expect(wake.disables, 0);
    await t.pumpWidget(const SizedBox.shrink());
    expect(wake.disables, 1);
  });

  testWidgets('shows Verifica in corso while a request is pending', (t) async {
    final gate = Completer<BadgeScanOutcome>();
    await t.pumpWidget(app(_GatedApi(gate)));
    emit('a');
    await t.pump();
    expect(find.text('Verifica in corso…'), findsOneWidget);
    gate.complete(_ok('Mario Rossi', BadgeScanAction.opened));
    await t.pumpAndSettle();
    expect(find.text('Verifica in corso…'), findsNothing);
    expect(find.text('ENTRATA registrata'), findsOneWidget);
  });

  testWidgets('camera unavailable shows the Italian message and does not crash', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: ScanUnavailable())));
    expect(
      find.text('Impossibile usare la fotocamera — controlla i permessi dell\'app'),
      findsOneWidget,
    );
  });
}

class _FakeWakelock implements BadgeWakelock {
  int enables = 0;
  int disables = 0;
  @override
  Future<void> enable() async => enables++;
  @override
  Future<void> disable() async => disables++;
}

class _GatedApi extends _FakeApi {
  _GatedApi(this.gate) : super(const {});
  final Completer<BadgeScanOutcome> gate;
  @override
  Future<BadgeScanOutcome> scan({
    required String cantiereId,
    required String token,
    required String clientScanId,
  }) => gate.future;
}
