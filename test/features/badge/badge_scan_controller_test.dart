import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/data/badge/badge_api_client.dart';
import 'package:tasktap_mobile/data/badge/badge_models.dart';
import 'package:tasktap_mobile/features/badge/badge_scan_controller.dart';

const _outcome = BadgeScanOutcome(
  result: BadgeScanResult.accepted,
  action: BadgeScanAction.opened,
  worker: BadgeWorker(displayName: 'Mario Rossi', employerName: 'Bianchi Srl'),
);

class _FakeApi implements BadgeApiClient {
  final calls = <({String cantiereId, String token, String clientScanId})>[];
  Completer<BadgeScanOutcome>? gate;
  Object? throwOnScan;

  @override
  Future<BadgeScanOutcome> scan({
    required String cantiereId,
    required String token,
    required String clientScanId,
  }) async {
    calls.add((cantiereId: cantiereId, token: token, clientScanId: clientScanId));
    if (gate != null) return gate!.future;
    if (throwOnScan != null) throw throwOnScan!;
    return _outcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeApi api;
  late DateTime now;
  late ProviderContainer container;

  BadgeScanController ctl() => container.read(badgeScanControllerProvider('c1').notifier);
  List<BadgeScanEntry> entries() => container.read(badgeScanControllerProvider('c1'));

  setUp(() {
    api = _FakeApi();
    now = DateTime.utc(2026, 10, 28, 8);
    container = ProviderContainer(
      overrides: [
        badgeApiClientProvider.overrideWithValue(api),
        badgeScanClockProvider.overrideWithValue(() => now),
      ],
    );
    container.listen(badgeScanControllerProvider('c1'), (_, _) {});
  });
  tearDown(() => container.dispose());

  test('same_code_in_frame_sends_one_request', () async {
    await ctl().onCode('tok-A');
    now = now.add(const Duration(seconds: 1));
    await ctl().onCode('tok-A');
    expect(api.calls, hasLength(1));
    expect(entries(), hasLength(1));
    // After the window the same code is handled again.
    now = now.add(const Duration(seconds: 3));
    await ctl().onCode('tok-A');
    expect(api.calls, hasLength(2));
  });

  test('next_code_scans_without_reopening', () async {
    await ctl().onCode('tok-A');
    now = now.add(const Duration(milliseconds: 200));
    await ctl().onCode('tok-B');
    expect(api.calls.map((c) => c.token), ['tok-A', 'tok-B']);
    expect(entries(), hasLength(2));
  });

  test('in_flight_ignores_new_codes', () async {
    api.gate = Completer<BadgeScanOutcome>();
    final first = ctl().onCode('tok-A');
    await ctl().onCode('tok-B');
    expect(api.calls, hasLength(1));
    api.gate!.complete(_outcome);
    await first;
    expect(entries(), hasLength(1));
    api.gate = null;
    await ctl().onCode('tok-B');
    expect(api.calls, hasLength(2));
  });

  test('each_attempt_has_unique_clientScanId', () async {
    await ctl().onCode('tok-A');
    await ctl().onCode('tok-B');
    await ctl().onCode('tok-C');
    final ids = api.calls.map((c) => c.clientScanId).toSet();
    expect(ids, hasLength(3));
    final v4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(ids.every(v4.hasMatch), isTrue);
    expect(api.calls.every((c) => c.cantiereId == 'c1'), isTrue);
  });

  test('entries are newest first', () async {
    await ctl().onCode('tok-A');
    api.throwOnScan = const BadgeApiException(statusCode: 403, code: 'NotLead', message: 'x');
    await ctl().onCode('tok-B');
    expect(entries().first.error?.isNotLead, isTrue);
    expect(entries().last.outcome, isNotNull);
  });

  test('BadgeApiException becomes an error entry', () async {
    api.throwOnScan = const BadgeApiException(message: 'offline', offline: true);
    await ctl().onCode('tok-A');
    expect(entries().single.error?.isOffline, isTrue);
    expect(entries().single.outcome, isNull);
  });

  test('a non-BadgeApiException error becomes an unexpected entry and does not throw', () async {
    api.throwOnScan = TypeError();
    await ctl().onCode('tok-A');
    final e = entries().single;
    expect(e.unexpectedError, isA<TypeError>());
    expect(e.outcome, isNull);
    expect(e.error, isNull);
    // The controller is not wedged: the next code still scans.
    api.throwOnScan = null;
    await ctl().onCode('tok-B');
    expect(entries().first.outcome, isNotNull);
  });

  test('a code resolving after the screen closed does not throw', () async {
    api.gate = Completer<BadgeScanOutcome>();
    final f = ctl().onCode('tok-A');
    container.dispose();
    api.gate!.complete(_outcome);
    await f;
  });
}
