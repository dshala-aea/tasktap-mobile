// Resume re-check: register a device whose permission/APNs token became available while the app
// was in the background. Fakes only; no lifecycle, no platform. It never prompts, and the in-app
// switch wins.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/crash_reporting/crash_reporter.dart';
import 'package:tasktap_mobile/core/notifications/push_reporting.dart';
import 'package:tasktap_mobile/core/notifications/push_resume_recheck.dart';

import '../../support/recording_crash_reporter.dart';

class _Rig {
  String? access = 'access-1';
  bool preference = true;
  bool granted = true;
  bool token = false;
  bool fetchSucceeds = true;
  int fetches = 0;
  final registered = <String>[];
  DateTime clock = DateTime.utc(2026, 11, 11, 10);
  Completer<void>? gate;

  late final recheck = PushResumeRecheck(
    accessToken: () => access,
    pushPreferenceEnabled: () async => preference,
    permissionGranted: () async => granted,
    hasToken: () => token,
    fetchToken: () async {
      fetches++;
      await gate?.future;
      token = fetchSucceeds;
      return fetchSucceeds;
    },
    register: (a) async => registered.add(a),
    now: () => clock,
  );
}

void main() {
  late RecordingCrashReporter reporter;
  late CrashReporter previous;
  setUp(() {
    previous = CrashReporter.instance;
    reporter = RecordingCrashReporter();
    CrashReporter.setInstance(reporter);
    resetPushReporting();
  });
  tearDown(() {
    CrashReporter.setInstance(previous);
    resetPushReporting();
  });

  test('resume + granted + no token: fetch, then register once', () async {
    final r = _Rig();
    await r.recheck.onResumed();
    expect(r.fetches, 1);
    expect(r.registered, ['access-1']);
    expect(reporter.messages.map((m) => m.message).join('\n'), contains('token obtained'));
  });

  test('resume + permission not granted: nothing fetched or registered, never prompts', () async {
    final r = _Rig()..granted = false;
    await r.recheck.onResumed();
    expect(r.fetches, 0);
    expect(r.registered, isEmpty);
    expect(reporter.messages.single.message, contains('not granted'));
    await r.recheck.onResumed();
    expect(reporter.messages, hasLength(1)); // onceKey: no Sentry spam
  });

  test('the in-app switch off wins over the re-check', () async {
    final r = _Rig()..preference = false;
    await r.recheck.onResumed();
    expect(r.fetches, 0);
    expect(r.registered, isEmpty);
  });

  test('signed out, or a token already held: nothing to do', () async {
    final out = _Rig()..access = null;
    await out.recheck.onResumed();
    final has = _Rig()..token = true;
    await has.recheck.onResumed();
    expect(out.fetches + has.fetches, 0);
    expect(out.registered + has.registered, isEmpty);
  });

  test('a resume while a fetch is in flight starts no second fetch', () async {
    final r = _Rig()..gate = Completer<void>();
    final first = r.recheck.onResumed();
    await Future<void>.delayed(Duration.zero);
    await r.recheck.onResumed();
    expect(r.fetches, 1);
    r.gate!.complete();
    await first;
    expect(r.registered, hasLength(1));
  });

  test('repeated failing resumes are backed off and capped', () async {
    final r = _Rig()..fetchSucceeds = false;
    await r.recheck.onResumed();
    await r.recheck.onResumed(); // immediately again: inside the backoff
    expect(r.fetches, 1);

    r.clock = r.clock.add(const Duration(seconds: 31));
    await r.recheck.onResumed();
    expect(r.fetches, 2);

    r.clock = r.clock.add(const Duration(seconds: 61));
    await r.recheck.onResumed();
    expect(r.fetches, 3);

    r.clock = r.clock.add(const Duration(days: 1));
    await r.recheck.onResumed(); // cap of 3 per run
    expect(r.fetches, 3);
    expect(r.registered, isEmpty);
  });

  test('a throwing dependency never escapes', () async {
    final r = PushResumeRecheck(
      accessToken: () => 'a',
      pushPreferenceEnabled: () async => throw StateError('prefs'),
      permissionGranted: () async => true,
      hasToken: () => false,
      fetchToken: () async => true,
      register: (_) async {},
    );
    await r.onResumed();
  });
}
