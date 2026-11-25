// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/update/app_version_evaluator.dart';
import 'package:tasktap_mobile/core/update/store_url.dart';
import 'package:tasktap_mobile/core/update/update_gate_rule.dart';

void main() {
  group('AppVersionEvaluator parity with the API', () {
    // (client, minimum, recommended, verdict): the same rows as AppVersionEvaluatorTests (C#).
    final rows = <(String?, String?, String?, AppVersionVerdict)>[
      ('1.0.11+42', '1.0.12', null, AppVersionVerdict.updateRequired),
      ('1.0.12+1', '1.0.12', null, AppVersionVerdict.ok),
      ('1.0.11', '1.0.11+50', null, AppVersionVerdict.updateRequired),
      ('1.0.11+7', '1.0.11+50', null, AppVersionVerdict.updateRequired),
      ('1.0.11+50', '1.0.11+50', null, AppVersionVerdict.ok),
      ('1.0.11+49', '1.0.11', null, AppVersionVerdict.ok),
      ('1.0.12+1', '1.0.12', '1.1.0', AppVersionVerdict.updateAvailable),
      ('1.2.0+1', '1.0.12', '1.1.0', AppVersionVerdict.ok),
      ('1.0.11+1', '1.0.11+5', '2.0.0', AppVersionVerdict.updateRequired),
      // numeric, not lexicographic
      ('1.0.9+1', '1.0.10', null, AppVersionVerdict.updateRequired),
      ('1.10.0+1', '1.9.0', null, AppVersionVerdict.ok),
      // no policy at all
      ('1.0.11+42', null, null, AppVersionVerdict.ok),
      // unparseable minimum / recommended never block
      ('1.0.11+42', 'abc', null, AppVersionVerdict.ok),
      ('1.0.11+42', '2.0', '3.0.0-beta', AppVersionVerdict.ok),
    ];

    for (final (client, min, rec, expected) in rows) {
      test('client $client, min $min, rec $rec -> $expected', () {
        expect(AppVersionEvaluator.evaluate(client, min, rec), expected);
      });
    }

    // Garbage client versions are never blocked, even against a minimum they would "fail".
    final garbage = <String?>['abc', '1.0', '1.0.0-beta', '', '１.0.0', null, '1.0.11\n', 'x' * 300];
    for (final g in garbage) {
      test('garbage client "$g" -> ok', () {
        expect(AppVersionEvaluator.evaluate(g, '99.0.0', '99.0.0'), AppVersionVerdict.ok);
      });
    }

    test('tryParse reads X.Y.Z and X.Y.Z+N', () {
      final a = AppVersionEvaluator.tryParse('1.0.11+42')!;
      expect((a.major, a.minor, a.patch, a.build), (1, 0, 11, 42));
      final b = AppVersionEvaluator.tryParse('2.3.4')!;
      expect((b.major, b.minor, b.patch, b.build), (2, 3, 4, null));
      expect(AppVersionEvaluator.tryParse('1.0.0+'), isNull);
      expect(AppVersionEvaluator.tryParse('1.0.0+1+2'), isNull);
      expect(AppVersionEvaluator.tryParse('1234567890.0.0'), isNull);
    });
  });

  group('updateGateMode truth table', () {
    test('not required: never forced, whatever is pending', () {
      for (final pending in [null, 0, 1, 7]) {
        expect(updateGateMode(updateRequired: false, pending: pending), UpdateGateMode.none);
      }
    });

    test('required and pending count unknown: not blocked', () {
      expect(updateGateMode(updateRequired: true, pending: null), UpdateGateMode.none);
    });

    test('required and pending > 0: sync first (banner, no block)', () {
      expect(updateGateMode(updateRequired: true, pending: 1), UpdateGateMode.syncFirst);
      expect(updateGateMode(updateRequired: true, pending: 4), UpdateGateMode.syncFirst);
    });

    test('required and nothing pending: blocked', () {
      expect(updateGateMode(updateRequired: true, pending: 0), UpdateGateMode.blocked);
    });
  });

  group('resolveStoreUri', () {
    test('policy https url wins', () {
      expect(
        resolveStoreUri(policyUrl: 'https://apps.apple.com/it/app/tasktap/id1', isIos: true),
        Uri.parse('https://apps.apple.com/it/app/tasktap/id1'),
      );
    });

    test('non-https or blank policy url falls back', () {
      for (final bad in [null, '', '  ', 'http://x.example/app', 'javascript:alert(1)', 'market://details?id=a']) {
        expect(
          resolveStoreUri(policyUrl: bad, isIos: true),
          Uri.parse('https://apps.apple.com/'),
          reason: '$bad',
        );
      }
    });

    test('android fallback is derived from the running package id', () {
      expect(
        resolveStoreUri(isIos: false, androidPackageName: 'com.example.app').toString(),
        'https://play.google.com/store/apps/details?id=com.example.app',
      );
      expect(
        resolveStoreUri(isIos: false, androidPackageName: ''),
        Uri.parse('https://play.google.com/store'),
      );
    });
  });
}
