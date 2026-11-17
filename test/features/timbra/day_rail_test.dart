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
import 'package:tasktap_mobile/data/timbratura/work_session_repository.dart'
    show reconciledOrphanMarker;
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart'
    show DayWorkLogEntry, DayWorkLogKind;
import 'package:tasktap_mobile/features/timbra/day_rail.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

WorkSession _event(
  String id,
  DateTime at,
  String type, {
  bool pending = false,
  String? notes,
}) => WorkSession(id: id, eventTime: at, eventType: type, isPendingSync: pending, notes: notes);

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

  group('reconciler mirrors', () {
    // The shape reported from the field: the reconciler had backfilled ingresso 09:20, pausa 13:08
    // and ripresa 14:16 from the server's own active shift, while the server also returned the
    // detailed rows those instants came from. The rail drew both and added both: 11h 09m "worked"
    // on a 6h 41m day.
    final shiftStart = DateTime.utc(2026, 11, 12, 8, 20); // 09:20 Rome (CET)
    final breakStart = DateTime.utc(2026, 11, 12, 12, 8); // 13:08
    final breakEnd = DateTime.utc(2026, 11, 12, 13, 16); // 14:16
    final now = DateTime.utc(2026, 11, 12, 15, 1); // 16:01

    WorkSession mirror(String id, DateTime at, String type) =>
        _event(id, at, type, pending: true, notes: reconciledOrphanMarker);

    test('mirrored shift events are not drawn as phone punches, so the day is not doubled', () {
      final day = buildDayRail(
        localEvents: [
          mirror('mirror-in', shiftStart, 'ingresso'),
          mirror('mirror-pausa', breakStart, 'pausa'),
          mirror('mirror-ripresa', breakEnd, 'ripresa'),
        ],
        serverRows: [
          _row('app-1', start: shiftStart, end: DateTime.utc(2026, 11, 12, 8, 35), sorgente: 'app'),
          _row(
            'app-2',
            start: DateTime.utc(2026, 11, 12, 8, 35),
            end: DateTime.utc(2026, 11, 12, 8, 36),
            kind: DayWorkLogKind.shortBreak,
            sorgente: 'app',
          ),
          _row(
            'app-3',
            start: DateTime.utc(2026, 11, 12, 8, 36),
            end: DateTime.utc(2026, 11, 12, 8, 37),
            sorgente: 'app',
          ),
          _row(
            'totem-1',
            start: DateTime.utc(2026, 11, 12, 8, 37),
            end: DateTime.utc(2026, 11, 12, 8, 42),
            kind: DayWorkLogKind.shortBreak,
            sorgente: 'totem',
          ),
          _row(
            'totem-2',
            start: DateTime.utc(2026, 11, 12, 8, 42),
            end: DateTime.utc(2026, 11, 12, 10, 22),
            sorgente: 'totem',
          ),
          _row(
            'totem-3',
            start: DateTime.utc(2026, 11, 12, 10, 22),
            end: DateTime.utc(2026, 11, 12, 10, 35),
            kind: DayWorkLogKind.shortBreak,
            sorgente: 'totem',
          ),
          _row(
            'totem-4',
            start: DateTime.utc(2026, 11, 12, 10, 35),
            end: breakStart,
            sorgente: 'totem',
          ),
          _row(
            'totem-5',
            start: breakStart,
            end: breakEnd,
            kind: DayWorkLogKind.longBreak,
            sorgente: 'totem',
          ),
          _row('totem-6', start: breakEnd, open: true, sorgente: 'totem'),
        ],
        now: now,
      );

      expect(day.entries.where((e) => e.origin == RailOrigin.phone), isEmpty);
      expect(day.entries.where((e) => e.pending), isEmpty);
      expect(day.entries, hasLength(9));
      // 15 + 1 + 1 + 5 + 100 + 13 + 93 + 105, with the short breaks paid (counted as worked).
      expect(day.worked, const Duration(minutes: 333));
      expect(day.paused, const Duration(minutes: 87));
      expect(day.worked, lessThanOrEqualTo(now.difference(shiftStart)));
    });
  });

  group('overlapping sources', () {
    // Two sources can describe overlapping time: a punch this phone queued offline and a totem
    // row for the same stretch, or an office correction over a phone interval. The mirror filter
    // above removes the common case; these guard the arithmetic when a genuine overlap remains.
    test('overlapping work and breaks are counted once, not summed', () {
      final day = buildDayRail(
        localEvents: [
          _event('in', _t8, 'ingresso'), // 06:00
          _event('pausa', _t12, 'pausa'), // 10:00
          _event('ripresa', _t13, 'ripresa'), // 11:00
          _event('fine', _t17, 'fine'), // 15:00
        ],
        serverRows: [
          _row('srv-work', start: _t13, end: _t17), // 11:00–15:00
          _row(
            'srv-break',
            start: _t12.add(const Duration(minutes: 30)),
            end: _t13.add(const Duration(minutes: 30)),
            kind: DayWorkLogKind.longBreak,
          ),
        ],
        now: DateTime.utc(2026, 7, 10, 18),
      );

      // Phone work 06–10 + 11–15; the server work row adds nothing new inside 11–15.
      expect(day.worked, const Duration(hours: 8));
      // Phone break 10–11 and server break 10:30–11:30 cover 10–11:30 once.
      expect(day.paused, const Duration(minutes: 90));
    });

    test('a long stretch still covers a later start, so no false gap is invented', () {
      final day = buildDayRail(
        localEvents: [
          _event('in', _t8, 'ingresso'), // 06:00
          _event('fine', DateTime.utc(2026, 7, 10, 12), 'fine'), // 14:00
        ],
        serverRows: [
          _row('srv-work', start: _t12, end: DateTime.utc(2026, 7, 10, 10)), // 10:00–12:00
          _row(
            'srv-break',
            start: DateTime.utc(2026, 7, 10, 10, 30),
            end: DateTime.utc(2026, 7, 10, 11),
            kind: DayWorkLogKind.longBreak,
          ),
        ],
        now: DateTime.utc(2026, 7, 10, 18),
      );

      expect(day.gaps, isEmpty);
    });

    test('the axis ends at the latest end, not at the last start', () {
      final now = DateTime.utc(2026, 7, 10, 14);
      final day = buildDayRail(
        localEvents: [_event('in', _t8, 'ingresso', pending: true)], // 06:00, still open
        serverRows: [
          _row(
            'srv',
            start: _t12,
            end: DateTime.utc(2026, 7, 10, 12),
          ), // 10:00–12:00, starts later
        ],
        now: now,
      );

      expect(day.axisEnd, now);
    });
  });
}
