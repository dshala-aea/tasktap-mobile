// ApnsDiagnostics: the native APNs outcome as Sentry tags. Fakes only; never throws, bounded,
// and silent (no channel call) off iOS.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/notifications/apns_diagnostics.dart';

void main() {
  test('an error recorded natively becomes the push.apns_error tag', () async {
    final d = ApnsDiagnostics(
      isIOS: true,
      invokeStatus: () async => {
        'registered': false,
        'error': 'NSCocoaErrorDomain:3000:no valid aps-environment entitlement',
      },
    );
    final t = await d.tags();
    expect(t['push.apns_error'], 'NSCocoaErrorDomain:3000:no valid aps-environment entitlement');
    expect(t['push.apns_registered'], 'false');
  });

  test('no error and a seen token reads none / true', () async {
    final d = ApnsDiagnostics(isIOS: true, invokeStatus: () async => {'registered': true});
    expect(await d.tags(), {'push.apns_error': 'none', 'push.apns_registered': 'true'});
  });

  test('silence (neither callback seen) reads none / false', () async {
    final d = ApnsDiagnostics(isIOS: true, invokeStatus: () async => {'registered': false});
    expect(await d.tags(), {'push.apns_error': 'none', 'push.apns_registered': 'false'});
  });

  test('a throwing channel reads unknown', () async {
    final d = ApnsDiagnostics(isIOS: true, invokeStatus: () async => throw StateError('boom'));
    expect(await d.tags(), {'push.apns_error': 'unknown', 'push.apns_registered': 'unknown'});
  });

  test('a malformed reply reads unknown', () async {
    final d = ApnsDiagnostics(isIOS: true, invokeStatus: () async => 'nope');
    expect((await d.tags())['push.apns_registered'], 'unknown');
  });

  test('a hung channel is abandoned after the timeout', () async {
    final d = ApnsDiagnostics(
      isIOS: true,
      timeout: const Duration(milliseconds: 20),
      invokeStatus: () => Completer<Object?>().future,
    );
    expect((await d.tags())['push.apns_error'], 'unknown');
  });

  test('an over-long error is capped at 200 characters', () async {
    final d = ApnsDiagnostics(
      isIOS: true,
      invokeStatus: () async => {'registered': false, 'error': 'x' * 500},
    );
    expect((await d.tags())['push.apns_error']!.length, 200);
  });

  test('Android is n/a and the channel is never called', () async {
    var calls = 0;
    final d = ApnsDiagnostics(
      isIOS: false,
      invokeStatus: () async {
        calls++;
        return {'registered': true};
      },
    );
    expect(await d.tags(), {'push.apns_error': 'n/a', 'push.apns_registered': 'n/a'});
    expect(calls, 0);
  });
}
