// test/data/timbratura/worklog_api_client_mobile_session_dto_test.dart
//
// Regression coverage for MobileSessionDto.toJson()'s UTC-conversion contract.
//
// Backend context (2026-09-22 payroll-data-integrity bug): a technician clocked in via mobile
// at 10:21 Rome-local (CEST, UTC+2) and the stored/displayed WorkLog start time came back as
// 8:21 — a silent 2-hour payroll shortfall. The root cause turned out to live entirely on the
// backend (WorkLogMobileSyncService.UpsertMobileSessionsAsync took the UTC wire value's raw
// `.TimeOfDay` instead of converting it back to Rome-local before storing it as a bare
// TimeSpan — fixed there). This mobile client was already correct: `PunchNotifier.punch()`
// captures `DateTime.now().toUtc()` (timbra_providers.dart) and `MobileSessionDto.toJson()`
// calls `.toUtc().toIso8601String()` again before putting it on the wire, so the JSON payload
// is always an unambiguous UTC instant (ISO 8601 with a trailing "Z"), never a local wall-clock
// value the backend could mistake for something else.
//
// This test pins that contract so a future edit cannot silently drop the `.toUtc()` call and
// start sending an ambiguous (no offset, no "Z") or raw-local timestamp instead — which is
// exactly the shape of bug this incident was about, just on the other side of the wire.

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';

void main() {
  group('MobileSessionDto.toJson', () {
    test('startTime is serialized as a UTC instant (trailing Z), not a raw local timestamp', () {
      // A wall-clock DateTime with no explicit UTC flag — exactly what `DateTime.now()` /
      // `DateTime.now().toUtc()` composition produces on a real device. We don't assume the
      // test host's timezone here: the property under test is "does toJson() call .toUtc()",
      // which holds regardless of what timezone the value started in.
      final local = DateTime(2026, 9, 22, 10, 21, 0);
      final dto = MobileSessionDto(clientId: 'c1', startTime: local);

      final json = dto.toJson();
      final wire = json['startTime'] as String;

      expect(wire, endsWith('Z'), reason: 'must be an unambiguous UTC instant on the wire');
      expect(wire, local.toUtc().toIso8601String());

      // Round-trips back to the exact same instant regardless of the reader's own timezone.
      final parsedBack = DateTime.parse(wire);
      expect(parsedBack.isUtc, isTrue);
      expect(parsedBack.toUtc(), local.toUtc());
    });

    test('endTime is likewise serialized as a UTC instant when present', () {
      final start = DateTime(2026, 9, 22, 10, 21, 0);
      final end = DateTime(2026, 9, 22, 11, 40, 0);
      final dto = MobileSessionDto(clientId: 'c1', startTime: start, endTime: end);

      final json = dto.toJson();
      final wire = json['endTime'] as String;

      expect(wire, endsWith('Z'));
      expect(wire, end.toUtc().toIso8601String());
    });

    test('endTime is null on the wire when the session is still open', () {
      final dto = MobileSessionDto(clientId: 'c1', startTime: DateTime(2026, 9, 22, 10, 21, 0));

      expect(dto.toJson()['endTime'], isNull);
    });

    test(
      'an already-UTC startTime round-trips unchanged (no double conversion)',
      () {
        // Guards the other direction: if a caller already has a UTC DateTime (e.g. from
        // DateTime.now().toUtc(), as PunchNotifier.punch() produces), toJson() must not shift it
        // again — .toUtc() on an already-UTC DateTime is a no-op, but this pins that explicitly.
        final alreadyUtc = DateTime.utc(2026, 9, 22, 8, 21, 0);
        final dto = MobileSessionDto(clientId: 'c1', startTime: alreadyUtc);

        expect(dto.toJson()['startTime'], '2026-09-22T08:21:00.000Z');
      },
    );
  });
}
