import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/time/business_time.dart';

BusinessTime _at(String zone, [DateTime? instant]) =>
    BusinessTime(zone, clock: instant == null ? null : () => instant);

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

void main() {
  group('utcRangeForBusinessDate Rome', () {
    final rome = _at('Europe/Rome');

    test('summer day', () {
      final (s, e) = rome.utcRangeForBusinessDate(_d(2026, 7, 10));
      expect(s, DateTime.utc(2026, 7, 9, 22));
      expect(e, DateTime.utc(2026, 7, 10, 22));
      expect(s.isUtc, isTrue);
      expect(e.isUtc, isTrue);
    });

    test('winter day', () {
      final (s, e) = rome.utcRangeForBusinessDate(_d(2026, 12, 1));
      expect(s, DateTime.utc(2026, 11, 30, 23));
      expect(e, DateTime.utc(2026, 12, 1, 23));
    });

    test('spring gap day is 23 h', () {
      final (s, e) = rome.utcRangeForBusinessDate(_d(2027, 3, 28));
      expect(s, DateTime.utc(2027, 3, 27, 23));
      expect(e, DateTime.utc(2027, 3, 28, 22));
      expect(e.difference(s), const Duration(hours: 23));
    });

    test('autumn repeat day is 25 h', () {
      final (s, e) = rome.utcRangeForBusinessDate(_d(2026, 10, 25));
      expect(s, DateTime.utc(2026, 10, 24, 22));
      expect(e, DateTime.utc(2026, 10, 25, 23));
      expect(e.difference(s), const Duration(hours: 25));
    });

    test('adjacent days tile around the transition', () {
      final (_, e1) = rome.utcRangeForBusinessDate(_d(2027, 3, 27));
      final (s2, e2) = rome.utcRangeForBusinessDate(_d(2027, 3, 28));
      final (s3, _) = rome.utcRangeForBusinessDate(_d(2027, 3, 29));
      expect(e1, s2);
      expect(e2, s3);
    });

    test('civilDate is read by y/m/d fields, local flag ignored', () {
      final (s, _) = rome.utcRangeForBusinessDate(
        DateTime(2026, 7, 10, 23, 59),
      );
      expect(s, DateTime.utc(2026, 7, 9, 22));
    });
  });

  group('other business zones', () {
    Duration len(String zone, DateTime d) {
      final (s, e) = _at(zone).utcRangeForBusinessDate(d);
      return e.difference(s);
    }

    test('America/Los_Angeles', () {
      expect(
        len('America/Los_Angeles', _d(2027, 3, 14)),
        const Duration(hours: 23),
      );
      expect(
        len('America/Los_Angeles', _d(2026, 11, 1)),
        const Duration(hours: 25),
      );
    });

    test('Pacific/Auckland', () {
      expect(
        len('Pacific/Auckland', _d(2026, 9, 27)),
        const Duration(hours: 23),
      );
      expect(
        len('Pacific/Auckland', _d(2027, 4, 4)),
        const Duration(hours: 25),
      );
    });
  });

  group('businessToday', () {
    DateTime today(DateTime clock, [String zone = 'Europe/Rome']) =>
        _at(zone, clock).businessToday();

    test('Rome boundaries', () {
      expect(today(DateTime.utc(2026, 7, 10, 21, 59, 59)), _d(2026, 7, 10));
      expect(today(DateTime.utc(2026, 7, 10, 22)), _d(2026, 7, 11));
      expect(today(DateTime.utc(2026, 10, 25, 0, 30)), _d(2026, 10, 25));
      expect(today(DateTime.utc(2026, 10, 25, 22, 59, 59)), _d(2026, 10, 25));
      expect(today(DateTime.utc(2026, 10, 25, 23)), _d(2026, 10, 26));
      expect(today(DateTime.utc(2027, 3, 28, 22)), _d(2027, 3, 29));
    });

    test('result is a UTC-flagged civil date', () {
      expect(today(DateTime.utc(2026, 7, 10, 12)).isUtc, isTrue);
    });

    test('local-flagged clock resolves from its instant', () {
      final instant = DateTime.utc(2026, 7, 10, 22);
      expect(today(instant.toLocal()), _d(2026, 7, 11));
    });
  });

  group('businessDateOf', () {
    DateTime dateOf(DateTime instant, [String zone = 'Europe/Rome']) =>
        _at(zone).businessDateOf(instant);

    test('Rome summer midnight boundary', () {
      expect(dateOf(DateTime.utc(2026, 7, 10, 21, 59, 59)), _d(2026, 7, 10));
      expect(dateOf(DateTime.utc(2026, 7, 10, 22)), _d(2026, 7, 11));
    });

    test('Rome winter midnight boundary', () {
      expect(dateOf(DateTime.utc(2026, 12, 1, 22, 59, 59)), _d(2026, 12, 1));
      expect(dateOf(DateTime.utc(2026, 12, 1, 23)), _d(2026, 12, 2));
    });

    test('Rome DST days: 2027-03-28 starts 23:00Z and ends 22:00Z', () {
      expect(dateOf(DateTime.utc(2027, 3, 27, 23)), _d(2027, 3, 28));
      expect(dateOf(DateTime.utc(2027, 3, 28, 21, 59)), _d(2027, 3, 28));
      expect(dateOf(DateTime.utc(2027, 3, 28, 22)), _d(2027, 3, 29));
    });

    test('Rome DST days: 2026-10-25 is 25 h long', () {
      expect(dateOf(DateTime.utc(2026, 10, 24, 22)), _d(2026, 10, 25));
      expect(dateOf(DateTime.utc(2026, 10, 25, 22, 59)), _d(2026, 10, 25));
      expect(dateOf(DateTime.utc(2026, 10, 25, 23)), _d(2026, 10, 26));
    });

    test('Los Angeles', () {
      const la = 'America/Los_Angeles';
      // 2026-07-10 07:00Z is 00:00 PDT.
      expect(dateOf(DateTime.utc(2026, 7, 10, 6, 59), la), _d(2026, 7, 9));
      expect(dateOf(DateTime.utc(2026, 7, 10, 7), la), _d(2026, 7, 10));
    });

    test('a UTC-boundary instant belongs to different dates per zone', () {
      final instant = DateTime.utc(2026, 7, 10, 23, 30);
      expect(dateOf(instant), _d(2026, 7, 11));
      expect(dateOf(instant, 'UTC'), _d(2026, 7, 10));
      expect(dateOf(instant, 'America/Los_Angeles'), _d(2026, 7, 10));
    });

    test('result is a UTC-flagged civil date and a local-flagged input is fine', () {
      final instant = DateTime.utc(2026, 7, 10, 22);
      expect(dateOf(instant).isUtc, isTrue);
      expect(dateOf(instant.toLocal()), _d(2026, 7, 11));
    });
  });

  group('todayRangeUtc', () {
    test('23 h day contains the clock instant', () {
      final now = DateTime.utc(2027, 3, 28, 10);
      final (s, e) = _at('Europe/Rome', now).todayRangeUtc();
      expect(e.difference(s), const Duration(hours: 23));
      expect(s.isAfter(now), isFalse);
      expect(e.isAfter(now), isTrue);
    });

    test('25 h day', () {
      final (s, e) = _at(
        'Europe/Rome',
        DateTime.utc(2026, 10, 25, 10),
      ).todayRangeUtc();
      expect(e.difference(s), const Duration(hours: 25));
    });
  });

  group('no midnight transition guard (spec 1.3)', () {
    for (final zone in [
      'Europe/Rome',
      'America/Los_Angeles',
      'Pacific/Auckland',
      'UTC',
    ]) {
      test(zone, () {
        final bt = _at(zone);
        var d = _d(2026, 1, 1);
        final last = _d(2028, 12, 31);
        while (!d.isAfter(last)) {
          final next = DateTime.utc(d.year, d.month, d.day + 1);
          final (s, e) = bt.utcRangeForBusinessDate(d);
          final (ns, _) = bt.utcRangeForBusinessDate(next);
          final local = bt.formatInZone(s, 'yyyy-MM-dd HH:mm');
          final expected =
              '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')} 00:00';
          expect(local, expected, reason: 'start of $d in $zone');
          expect(e, ns, reason: 'end of $d tiles with next start in $zone');
          d = next;
        }
      });
    }
  });

  group('formatInZone', () {
    final rome = _at('Europe/Rome');

    test('summer and winter', () {
      expect(rome.formatInZone(DateTime.utc(2026, 7, 10, 6), 'HH:mm'), '08:00');
      expect(rome.formatInZone(DateTime.utc(2026, 12, 1, 7), 'HH:mm'), '08:00');
    });

    test('repeated hour shows the same label for two instants', () {
      expect(
        rome.formatInZone(DateTime.utc(2026, 10, 25, 0, 30), 'HH:mm'),
        '02:30',
      );
      expect(
        rome.formatInZone(DateTime.utc(2026, 10, 25, 1, 30), 'HH:mm'),
        '02:30',
      );
    });

    test('crosses midnight into the zone date', () {
      expect(
        rome.formatInZone(DateTime.utc(2026, 10, 24, 22, 30), 'dd/MM HH:mm'),
        '25/10 00:30',
      );
    });

    test('time that is a gap on the DEVICE zone is not shifted', () {
      // 02:30 in New York on 2027-03-28 does not exist in Rome (device gap).
      expect(
          _at('America/New_York')
              .formatInZone(DateTime.utc(2027, 3, 28, 6, 30), 'HH:mm'),
          '02:30');
    });

    test('midnight prints 00:00', () {
      expect(rome.formatInZone(DateTime.utc(2026, 7, 9, 22), 'HH:mm'), '00:00');
    });

    test('local-flagged instant equals its UTC twin', () {
      final utc = DateTime.utc(2026, 7, 10, 6);
      expect(
        rome.formatInZone(utc.toLocal(), 'HH:mm'),
        rome.formatInZone(utc, 'HH:mm'),
      );
    });
  });

  group('instantOfLegacyLabel', () {
    final rome = _at('Europe/Rome');

    test('summer and winter', () {
      expect(
        rome.instantOfLegacyLabel(_d(2026, 7, 10), const Duration(hours: 8)),
        DateTime.utc(2026, 7, 10, 6),
      );
      expect(
        rome.instantOfLegacyLabel(_d(2026, 12, 1), const Duration(hours: 8)),
        DateTime.utc(2026, 12, 1, 7),
      );
    });

    test('26 h overflows to the next day', () {
      expect(
        rome.instantOfLegacyLabel(_d(2026, 7, 10), const Duration(hours: 26)),
        DateTime.utc(2026, 7, 11, 0),
      );
    });

    test('result is UTC', () {
      expect(
        rome
            .instantOfLegacyLabel(_d(2026, 7, 10), const Duration(hours: 8))
            .isUtc,
        isTrue,
      );
    });

    test('ambiguous 02:30 round-trips to the same label', () {
      final r = rome.instantOfLegacyLabel(
        _d(2026, 10, 25),
        const Duration(hours: 2, minutes: 30),
      );
      expect(
        r == DateTime.utc(2026, 10, 25, 0, 30) ||
            r == DateTime.utc(2026, 10, 25, 1, 30),
        isTrue,
      );
      expect(r, DateTime.utc(2026, 10, 25, 1, 30));
      expect(rome.formatInZone(r, 'HH:mm'), '02:30');
    });

    test('gap 02:30 does not throw and lands on the same zone date', () {
      late DateTime r;
      expect(
        () => r = rome.instantOfLegacyLabel(
          _d(2027, 3, 28),
          const Duration(hours: 2, minutes: 30),
        ),
        returnsNormally,
      );
      expect(rome.formatInZone(r, 'yyyy-MM-dd'), '2027-03-28');
      expect(r, DateTime.utc(2027, 3, 28, 1, 30)); // forward shift to 03:30
    });
  });

  group('legacy frame is Rome, not the tenant zone', () {
    for (final zone in ['America/New_York', 'Asia/Tokyo', 'UTC']) {
      test('instantOfLegacyLabel under $zone', () {
        expect(
          _at(
            zone,
          ).instantOfLegacyLabel(_d(2026, 7, 10), const Duration(hours: 8)),
          DateTime.utc(2026, 7, 10, 6),
        );
      });
    }

    final clock = DateTime.utc(2026, 7, 10, 22, 30);
    for (final zone in ['America/New_York', 'UTC', 'Europe/Rome']) {
      test('legacyToday under $zone is the Rome date', () {
        expect(_at(zone, clock).legacyToday(), _d(2026, 7, 11));
      });
    }

    test('businessToday for New York differs', () {
      expect(_at('America/New_York', clock).businessToday(), _d(2026, 7, 10));
    });
  });

  group('construction', () {
    test('zone id is resolved', () {
      expect(_at('Mars/Olympus').zoneId, 'Europe/Rome');
      expect(_at('Asia/Tokyo').zoneId, 'Asia/Tokyo');
      expect(_at('Asia/Tokyo').location.name, 'Asia/Tokyo');
    });

    test('fallback is Rome', () {
      expect(BusinessTime.fallback().zoneId, 'Europe/Rome');
    });

    test('kLegacyLabelZoneId', () {
      expect(kLegacyLabelZoneId, 'Europe/Rome');
    });
  });
}
