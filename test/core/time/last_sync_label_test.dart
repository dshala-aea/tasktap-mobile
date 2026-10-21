import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/last_sync_label.dart';

void main() {
  // All values are local DateTimes, which is what the formatter reads after `toLocal()`. `now` is
  // injected so the cases are fixed rather than relative to the machine clock.
  final now = DateTime(2026, 10, 21, 18, 0);

  group('formatLastSyncLabel', () {
    test('never synced reads "Mai"', () {
      expect(formatLastSyncLabel(null, now: now), 'Mai');
    });

    test('today names the time', () {
      expect(
        formatLastSyncLabel(DateTime(2026, 10, 21, 14, 32), now: now),
        'Oggi alle 14:32',
      );
    });

    test('yesterday names the time', () {
      expect(
        formatLastSyncLabel(DateTime(2026, 10, 20, 9, 10), now: now),
        'Ieri alle 09:10',
      );
    });

    test('two to six days ago is a day count', () {
      expect(
        formatLastSyncLabel(DateTime(2026, 10, 18, 9, 10), now: now),
        '3 giorni fa',
      );
    });

    test('a week or more is the date itself', () {
      expect(
        formatLastSyncLabel(DateTime(2026, 10, 12, 9, 10), now: now),
        '12/10/2026',
      );
    });

    test('the day count stops at exactly seven days', () {
      expect(
        formatLastSyncLabel(DateTime(2026, 10, 15, 9, 10), now: now),
        '6 giorni fa',
      );
      expect(
        formatLastSyncLabel(DateTime(2026, 10, 14, 9, 10), now: now),
        '14/10/2026',
      );
    });

    test('a timestamp ahead of the clock reads as a date, never a negative count', () {
      expect(
        formatLastSyncLabel(DateTime(2026, 10, 22, 8, 0), now: now),
        '22/10/2026',
      );
    });
  });
}
