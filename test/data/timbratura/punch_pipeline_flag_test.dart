// dart format width=100
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasktap_mobile/data/timbratura/punch_pipeline_flag.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('unknown session, nothing stored and nobody signed in all mean the legacy path', () async {
    final flag = PunchPipelineFlag();
    expect(await flag.read(null), isFalse);
    expect(await flag.read('u1'), isFalse);
  });

  test('the answer is kept per session: another tenant on a shared device does not inherit it', () async {
    final flag = PunchPipelineFlag();
    await flag.write('u1', true);

    expect(await flag.read('u1'), isTrue);
    expect(await flag.read('u2'), isFalse);

    await flag.write('u1', false);
    expect(await flag.read('u1'), isFalse);
  });

  test('a store that throws reads as off and never fails the caller', () async {
    final flag = PunchPipelineFlag(prefs: () async => throw StateError('no prefs'));
    expect(await flag.read('u1'), isFalse);
    await flag.write('u1', true); // must not throw
  });
}
