// The phone's copy of "the server says my clock was off".
//
// Only the server can answer that question — it alone sees the receipt instant — so this notifier
// is a plain in-memory relay: two responses write into it, the timer bar reads out of it. The tests
// pin the two things that can go wrong in a relay: it must not notify for an unchanged value (every
// retry of the same batch reports the same gap), and it must not let one ticket's number leak onto
// another's.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/presentation/providers/clock_disagreement_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  ClockDisagreementNotifier notifier() =>
      container.read(clockDisagreementProvider.notifier);

  test('records the gap the server reported, per ticket', () {
    notifier().record('t1', 720);

    expect(container.read(clockDisagreementProvider), {'t1': 720});
  });

  test('a retry that reports the same gap changes nothing', () {
    notifier().record('t1', 720);
    var rebuilds = 0;
    container.listen(clockDisagreementProvider, (_, _) => rebuilds++);

    notifier().record('t1', 720);

    expect(rebuilds, 0, reason: 'the queued batch is re-sent on every sync with the same answer');
  });

  test('a later disagreement for another ticket leaves the first one alone', () {
    notifier().record('t1', 720);
    notifier().record('t2', -1800);

    expect(container.read(clockDisagreementProvider), {'t1': 720, 't2': -1800});
  });

  test('dismissing one ticket does not silence another', () {
    notifier().record('t1', 720);
    notifier().record('t2', -1800);

    notifier().dismiss('t1');

    expect(container.read(clockDisagreementProvider), {'t2': -1800});
  });

  test('dismissing a ticket with no warning is a no-op', () {
    var rebuilds = 0;
    container.listen(clockDisagreementProvider, (_, _) => rebuilds++);

    notifier().dismiss('never-seen');

    expect(rebuilds, 0);
    expect(container.read(clockDisagreementProvider), isEmpty);
  });

  group('the punch-screen banners', () {
    test('record the gap, and a retried batch reporting it again changes nothing', () {
      final n = container.read(timbraClockDisagreementProvider.notifier);
      n.record(720);
      var rebuilds = 0;
      container.listen(timbraClockDisagreementProvider, (_, _) => rebuilds++);

      n.record(720);

      expect(container.read(timbraClockDisagreementProvider), 720);
      expect(rebuilds, 0, reason: 'the queued batch is re-sent on every sync with the same answer');
    });

    test('dismiss clears the banner; the server keeps the record', () {
      final n = container.read(timbraClockDisagreementProvider.notifier);
      n.record(720);

      n.dismiss();

      expect(container.read(timbraClockDisagreementProvider), isNull);
    });

    test('the cantiere banner is not the plain-timbra banner', () {
      container.read(timbraClockDisagreementProvider.notifier).record(720);

      container.read(cantiereClockDisagreementProvider.notifier).record(-1800);

      expect(container.read(timbraClockDisagreementProvider), 720);
      expect(container.read(cantiereClockDisagreementProvider), -1800);
    });
  });

  group('describeClockDisagreement', () {
    test('states direction as a disagreement, never as an accusation', () {
      expect(describeClockDisagreement(720), '12 min avanti');
      expect(describeClockDisagreement(-1800), '30 min indietro');
    });

    test('truncates, like the office column, and never rounds up past the threshold', () {
      // 10 min 59 s is still "10 min": rounding to 11 would misstate a number the server already
      // decided about, and the threshold itself is expressed in whole minutes.
      expect(describeClockDisagreement(659), '10 min avanti');
      expect(describeClockDisagreement(-601), '10 min indietro');
    });
  });
}
