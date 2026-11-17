import 'package:firebase_messaging/firebase_messaging.dart' show AuthorizationStatus;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/core/notifications/push_launch_permission.dart';
import 'package:tasktap_mobile/core/notifications/push_resume_recheck.dart'
    show kPushPreferenceKey;

PushLaunchPermission _make(
  AuthorizationStatus status,
  List<String> log, {
  bool grant = true,
  bool throwOnAsk = false,
}) => PushLaunchPermission(
  status: () async => status,
  ask: () async {
    log.add('ask');
    if (throwOnAsk) throw StateError('platform');
    return grant;
  },
  onDone: (g) async => log.add('done:$g'),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('asks once when the OS has never been asked', () async {
    final log = <String>[];
    expect(await _make(AuthorizationStatus.notDetermined, log).run(), isTrue);
    expect(log, ['ask', 'done:true']);
  });

  for (final s in [
    AuthorizationStatus.authorized,
    AuthorizationStatus.denied,
    AuthorizationStatus.provisional,
  ]) {
    test('does nothing when status is ${s.name}', () async {
      final log = <String>[];
      expect(await _make(s, log).run(), isFalse);
      expect(log, isEmpty);
    });
  }

  test('does nothing when the in-app switch is off', () async {
    SharedPreferences.setMockInitialValues({kPushPreferenceKey: false});
    final log = <String>[];
    expect(await _make(AuthorizationStatus.notDetermined, log).run(), isFalse);
    expect(log, isEmpty);
  });

  test('does not ask twice across launches (persisted flag)', () async {
    final log = <String>[];
    await _make(AuthorizationStatus.notDetermined, log, grant: false).run();
    log.clear();
    // Second launch: even if the OS still reports notDetermined, the flag blocks it.
    expect(await _make(AuthorizationStatus.notDetermined, log).run(), isFalse);
    expect(log, isEmpty);
  });

  test('a failing ask never throws and is not retried', () async {
    final log = <String>[];
    await expectLater(
      _make(AuthorizationStatus.notDetermined, log, throwOnAsk: true).run(),
      completes,
    );
    expect(log, ['ask', 'done:false']);
    log.clear();
    expect(await _make(AuthorizationStatus.notDetermined, log).run(), isFalse);
  });

  testWidgets('runs only after the first frame when scheduled post-frame', (tester) async {
    final log = <String>[];
    final p = _make(AuthorizationStatus.notDetermined, log);
    var built = false;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) => p.run());
            built = true;
            return const SizedBox();
          },
        ),
      );
      expect(built, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(log, ['ask', 'done:true']);
  });
}
