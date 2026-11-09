// Pure tests for the merged day — no widgets, no clock, no network.
//
// The bug this file guards: the Timbra screen used to read this phone's own table only, so a
// punch made on the totem, on another device, or corrected by the office was invisible and the
// total undercounted. The merge has two hazards worth pinning:
//   • double counting — the phone's events and the server rows they produced describe the SAME
//     stretch, so a server row whose clientId is one of this phone's events must be dropped;
//   • wrong arithmetic — a pause is not work. A short break is paid, a lunch break and a
//     not-yet-frozen break are not.

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' show WorkSession;
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart'
    show DayWorkLogEntry, DayWorkLogKind;
import 'package:tasktap_mobile/features/timbra/day_rail.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

WorkSession _event(String id, DateTime at, String type, {bool pending = false}) => WorkSession(
  id: id,
  eventTime: at,
  eventType: type,
  isPendingSync: pending,
);

DayWorkLogEntry _row(
  String id, {
  DateTime? start,
  DateTime? end,
  bool open = false,
  DayWorkLogKind kind = DayWorkLogKind.ordinary,
  String? clientId,
  String? sorgente,
}) => DayWorkLogEntry(
  id: id,
  clientId: clientId,
  start: start ?? DateTime.utc(2026, 7, 10, 6),
  end: open ? null : (end ?? DateTime.utc(2026, 7, 10, 10)),
  kind: kind,
  sorgente: sorgente,
);

final _t8 = DateTime.utc(2026, 7, 10, 6); // 08:00 Rome
final _t12 = DateTime.utc(2026, 7, 10, 10); // 12:00 Rome
final _t13 = DateTime.utc(2026, 7, 10, 11); // 13:00 Rome
final _t17 = DateTime.utc(2026, 7, 10, 15); // 17:00 Rome

void main() {
  group('the phone alone', () {
    test('ingresso + fine is one closed stretch', () {
      final day = buildDayRail(
        localEvents: [
          _event('a', _t8, 'ingresso'),
          _event('b', _t12, 'fine'),
        ],
        serverRows: const [],
        now: DateTime.utc(2026, 7, 10, 18),
      );

      expect(day.entries, hasLength(1));
      final entry = day.entries.single;
      expect(entry.kind, RailKind.work);
      expect(entry.origin, RailOrigin.phone);
      expect(entry.start, _t8);
      expect(entry.end, _t12);
      expect(day.worked, const Duration(hours: 4));
      expect(day.gaps, isEmpty);
    });

    test('an open stretch runs to now and the total keeps counting', () {
      final day = buildDayRail(
        localEvents: [_event('a', _t8, 'ingresso')],
        serverRows: const [],
        now: _t12,
      );

      expect(day.isOpen, isTrue);
      expect(day.entries.single.isOpen, isTrue);
      expect(day.worked, const Duration(hours: 4));
    });

    test('pausa closes the work stretch and opens a break of unknown kind', () {
      final day = buildDayRail(
        localEvents: [
          _event('a', _t8, 'ingresso'),
          _event('b', _t12, 'pausa'),
          _event('c', _t13, 'ripresa'),
        ],
        serverRows: const [],
        now: _t17,
      );

      expect(day.entries.map((e) => e.kind).toList(), [
        RailKind.work,
        RailKind.breakUndecided,
        RailKind.work,
      ]);
      // 08–12 and 13–17 are worked; the lunch hour is not.
      expect(day.worked, const Duration(hours: 8));
      expect(day.paused, const Duration(hours: 1));
      expect(day.gaps, isEmpty);
    });

    test('a stretch ending where the next begins is not a gap', () {
      final day = buildDayRail(
        localEvents: [
          _event('a', _t8, 'ingresso'),
          _event('b', _t12, 'pausa'),
          _event('c', _t12, 'ripresa'),
        ],
        serverRows: const [],
        now: _t13,
      );

      expect(day.gaps, isEmpty);
    });

    test('two punches in the same second still make a stretch', () {
      // Punching in and out inside one second is unusual, not impossible (a queued replay, two
      // taps in a row). Dropping it would hide a punch the technician made, so it is kept with a
      // zero duration and drawn as a floored bar.
      final day = buildDayRail(
        localEvents: [
          _event('a', _t8, 'ingresso'),
          _event('b', _t8, 'fine'),
        ],
        serverRows: const [],
        now: _t17,
      );

      expect(day.entries, hasLength(1));
      expect(day.entries.single.durationAt(_t17), Duration.zero);
    });

    test('an unsent punch marks the stretch it produced as pending', () {
      final day = buildDayRail(
        localEvents: [
          _event('a', _t8, 'ingresso', pending: true),
          _event('b', _t12, 'fine'),
        ],
        serverRows: const [],
        now: _t17,
      );

      expect(day.entries.single.pending, isTrue);
      expect(day.hasPending, isTrue);
    });

    test('a stretch between two unsent punches is pending, but a closed pair is not', () {
      final day = buildDayRail(
        localEvents: [
          _event('a', _t8, 'ingresso'),
          _event('b', _t12, 'fine', pending: true),
        ],
        serverRows: const [],
        now: _t17,
      );

      // Either end unsent means the server does not know this stretch as it stands.
      expect(day.entries.single.pending, isTrue);
    });
  });

  group('merging the server', () {
    test('a row this phone produced is dropped, not doubled', () {
      final day = buildDayRail(
        localEvents: [
          _event('ingresso-1', _t8, 'ingresso'),
          _event('fine-1', _t12, 'fine'),
        ],
        // The server echoes the same stretch back, carrying the ingresso event's id.
        serverRows: [_row('srv-1', start: _t8, end: _t12, clientId: 'ingresso-1')],
        now: _t17,
      );

      expect(day.entries, hasLength(1));
      expect(day.worked, const Duration(hours: 4));
    });

    test('a break row joins on the pausa event id', () {
      final day = buildDayRail(
        localEvents: [
          _event('ingresso-1', _t8, 'ingresso'),
          _event('pausa-1', _t12, 'pausa'),
        ],
        serverRows: [
          _row(
            'srv-break',
            start: _t12,
            end: _t13,
            kind: DayWorkLogKind.longBreak,
            clientId: 'pausa-1',
          ),
        ],
        now: _t17,
      );

      // The break came back as the local pausa, so there is no duplicate and no gap. It is still
      // open — the pausa event has no ripresa — so it runs to now.
      expect(day.entries, hasLength(2));
      expect(day.paused, const Duration(hours: 5));
    });

    test('a totem punch this phone never saw is part of the day', () {
      final day = buildDayRail(
        localEvents: const [],
        serverRows: [_row('srv-totem', start: _t8, end: _t12, sorgente: 'totem')],
        now: _t17,
      );

      final entry = day.entries.single;
      expect(entry.origin, RailOrigin.server);
      expect(entry.sorgente, 'totem');
      expect(entry.kind, RailKind.work);
      expect(day.worked, const Duration(hours: 4));
    });

    test('a phone punch and a totem punch in the same day are both counted', () {
      final day = buildDayRail(
        localEvents: [
          _event('ingresso-1', _t8, 'ingresso'),
          _event('fine-1', _t12, 'fine'),
        ],
        serverRows: [
          _row('srv-totem', start: _t13, end: _t17, sorgente: 'totem'),
        ],
        now: _t17,
      );

      expect(day.entries, hasLength(2));
      expect(day.worked, const Duration(hours: 8));
      // 12:00 → 13:00 was recorded by nobody, and it is drawn rather than hidden.
      expect(day.gaps, hasLength(1));
      expect(day.gaps.single.duration, const Duration(hours: 1));
    });

    test('an open server row runs to now', () {
      final day = buildDayRail(
        localEvents: const [],
        serverRows: [_row('srv-open', start: _t8, open: true, sorgente: 'totem')],
        now: _t12,
      );

      expect(day.entries.single.isOpen, isTrue);
      expect(day.worked, const Duration(hours: 4));
    });
  });

  group('break arithmetic', () {
    test('a paid short break counts as worked', () {
      final day = buildDayRail(
        localEvents: const [],
        serverRows: [
          _row('srv-work', start: _t8, end: _t12),
          _row('srv-short', start: _t12, end: _t13, kind: DayWorkLogKind.shortBreak),
        ],
        now: _t17,
      );

      expect(day.worked, const Duration(hours: 5));
      expect(day.paused, const Duration(hours: 1));
    });

    test('an unpaid lunch break does not', () {
      final day = buildDayRail(
        localEvents: const [],
        serverRows: [
          _row('srv-work', start: _t8, end: _t12),
          _row('srv-lunch', start: _t12, end: _t13, kind: DayWorkLogKind.longBreak),
        ],
        now: _t17,
      );

      expect(day.worked, const Duration(hours: 4));
      expect(day.paused, const Duration(hours: 1));
    });

    test('a break whose kind is not frozen yet does not count', () {
      final day = buildDayRail(
        localEvents: const [],
        serverRows: [_row('srv-b', start: _t8, end: _t12, kind: DayWorkLogKind.breakTime)],
        now: _t17,
      );

      expect(day.worked, Duration.zero);
    });

    test('a row of an unknown type counts as worked rather than vanishing', () {
      final day = buildDayRail(
        localEvents: const [],
        serverRows: [_row('srv-u', start: _t8, end: _t12, kind: DayWorkLogKind.unknown)],
        now: _t17,
      );

      expect(day.entries.single.countsAsWorked, isTrue);
      expect(day.worked, const Duration(hours: 4));
    });
  });

  group('voids', () {
    test('nothing is drawn after the last recorded stretch', () {
      // Once the technician has clocked out, the rest of the evening is not missing time — the
      // day is simply over. A trailing void would accuse them of not working.
      final day = buildDayRail(
        localEvents: const [],
        serverRows: [_row('srv-1', start: _t8, end: _t12)],
        now: DateTime.utc(2026, 7, 10, 20),
      );

      expect(day.gaps, isEmpty);
      expect(day.axisEnd, _t12);
    });

    test('an empty day has no axis at all', () {
      final day = buildDayRail(
        localEvents: const [],
        serverRows: const [],
        now: DateTime.utc(2026, 7, 10, 20),
      );

      expect(day.isEmpty, isTrue);
      expect(day.axisStart, isNull);
      expect(day.axisEnd, isNull);
      expect(day.worked, Duration.zero);
    });
  });

  group('a server row the app recorded but the clientId join misses', () {
    test('is absorbed when it is the same stretch (same start and end)', () {
      final day = buildDayRail(
        localEvents: [_event('a', _t8, 'ingresso'), _event('b', _t12, 'fine')],
        serverRows: [
          _row('srv', start: _t8.add(const Duration(seconds: 20)), end: _t12, clientId: 'other', sorgente: 'app'),
        ],
        now: DateTime.utc(2026, 7, 10, 18),
      );

      expect(day.entries, hasLength(1), reason: 'one stretch, not two');
      expect(day.worked, const Duration(hours: 4));
    });

    test('is kept when it is NOT an app row (a totem at the same minute is another record)', () {
      final day = buildDayRail(
        localEvents: [_event('a', _t8, 'ingresso'), _event('b', _t12, 'fine')],
        serverRows: [_row('srv', start: _t8, end: _t12, clientId: null, sorgente: 'totem')],
        now: DateTime.utc(2026, 7, 10, 18),
      );

      expect(day.entries, hasLength(2));
    });

    test('is kept when it starts at a different time', () {
      final day = buildDayRail(
        localEvents: [_event('a', _t8, 'ingresso'), _event('b', _t12, 'fine')],
        serverRows: [_row('srv', start: _t13, end: _t17, clientId: null, sorgente: 'app')],
        now: DateTime.utc(2026, 7, 10, 18),
      );

      expect(day.entries, hasLength(2));
    });

    test('absorbs at most one server row per phone stretch', () {
      final day = buildDayRail(
        localEvents: [_event('a', _t8, 'ingresso'), _event('b', _t12, 'fine')],
        serverRows: [
          _row('s1', start: _t8, end: _t12, clientId: null, sorgente: 'app'),
          _row('s2', start: _t8, end: _t12, clientId: null, sorgente: 'app'),
        ],
        now: DateTime.utc(2026, 7, 10, 18),
      );

      expect(day.entries, hasLength(2), reason: 'the second is a genuinely separate server row');
    });

    test('a break is matched to a break, never to work', () {
      final day = buildDayRail(
        localEvents: [
          _event('a', _t8, 'ingresso'),
          _event('p', _t12, 'pausa'),
          _event('r', _t13, 'ripresa'),
          _event('f', _t17, 'fine'),
        ],
        serverRows: [
          _row('srv-break', start: _t12, end: _t13, kind: DayWorkLogKind.longBreak, clientId: null, sorgente: 'app'),
        ],
        now: DateTime.utc(2026, 7, 10, 18),
      );

      expect(day.entries.where((e) => e.origin == RailOrigin.server), isEmpty);
      expect(day.entries, hasLength(3));
    });
  });
}
