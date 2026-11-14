// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// The day as a line
//
// The Timbra screen used to show only the punches this phone recorded: a totem punch, a punch
// from another device and an office correction were all invisible, and the total underneath was
// the sum of what was left. This file is the fix, as a pure function so it can be reasoned about
// and tested without a widget, a network or a clock.
//
// Two sources describe the same day in two different shapes:
//
//   • the phone holds EVENTS — ingresso / pausa / ripresa / fine, each its own row, some not yet
//     sent;
//   • the server holds INTERVALS — a row per stretch, with a type (work, short break, lunch) and
//     an origin (totem, QR, app, office).
//
// They are not two lists to concatenate. The phone's ingresso→fine pair and the server row it
// produced describe ONE stretch, and showing both doubles the day. The join key is the client id:
// the server stores the client-generated event id on the row it created, so a server row whose
// clientId is one of this phone's events is already in the local list and is dropped here.
//
// What survives is exactly: every stretch this phone knows about, plus every stretch it does
// not — which is the set the rail draws.
//
// ORDINARY ATTENDANCE ONLY. Cantiere time is a different record of the day (`CantiereWorkLog`,
// written by the cantiere screen and the badge/totem flows, with its own payroll treatment); it is
// NOT merged here, so a day spent on a cantiere can read short on this screen. That is the ruled
// boundary (2026-11-04), not an omission: this surface is the technician's simple timbratura, and
// the office pays cantiere hours through their own. Do not "fix" a short day by folding those rows
// in — that is a product decision with payroll consequences, not a bug fix.
// ══════════════════════════════════════════════════════════════════════════════

import '../../data/local/app_database.dart' show WorkSession;
import '../../data/timbratura/work_session_repository.dart' show reconciledOrphanMarker;
import '../../data/timbratura/worklog_api_client.dart' show DayWorkLogEntry, DayWorkLogKind;

/// What a stretch of the day was.
enum RailKind {
  /// Ordinary attendance (`Ordinary`).
  work,

  /// A paid pause (`ShortBreak`): counted in the day's worked total, excluded from the weekly
  /// overtime threshold (D.Lgs. 66/2003 — a pausa is not orario di lavoro).
  breakShort,

  /// A lunch break (`LongBreak`): unpaid, out of both the worked total and `OreTotal`.
  breakLong,

  /// A break whose kind is not frozen yet — the row is still open, or it predates kinds
  /// altogether (those are always counted as lunch, unpaid, so the historical payroll does not
  /// move). Never counted as worked here.
  breakUndecided,

  /// A server row that did not say what it was (an older backend). Counted as worked, because
  /// the alternative is hiding time the office has on record.
  unknown,
}

/// Who recorded the stretch.
enum RailOrigin {
  /// Recorded on this phone.
  phone,

  /// Known only from the server: a totem, another device, or the office.
  server,
}

/// One stretch of the day, as the rail draws it.
class RailEntry {
  const RailEntry({
    required this.kind,
    required this.start,
    required this.end,
    required this.origin,
    required this.pending,
    this.sorgente,
  });

  final RailKind kind;
  final DateTime start;

  /// Null while the stretch is still running: it is drawn up to "now".
  final DateTime? end;

  final RailOrigin origin;

  /// Recorded here but not yet accepted by the server.
  final bool pending;

  /// `totem` | `qr` | `app` | `manuale` on a server row, null otherwise.
  final String? sorgente;

  bool get isOpen => end == null;

  /// The stretch's end, or [now] while it runs.
  DateTime endOr(DateTime now) => end ?? now;

  Duration durationAt(DateTime now) {
    final e = endOr(now);
    final d = e.difference(start);
    return d.isNegative ? Duration.zero : d;
  }

  /// Counted in the day's worked total: ordinary work, an unknown server row, and a paid pause.
  /// An undecided or lunch break is not.
  bool get countsAsWorked =>
      kind == RailKind.work || kind == RailKind.unknown || kind == RailKind.breakShort;
}

/// An unaccounted stretch BETWEEN two recorded ones — the day's voids.
///
/// Deliberately not produced after the last recorded stretch: once the technician has clocked
/// out, the rest of the evening is not missing time, the day is simply over. A void only exists
/// when the day resumed after it.
class RailGap {
  const RailGap({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}

/// The day, ready to draw.
class DayRail {
  const DayRail({required this.entries, required this.gaps, required this.now});

  final List<RailEntry> entries;
  final List<RailGap> gaps;
  final DateTime now;

  bool get isEmpty => entries.isEmpty;

  /// Whether anything is still running.
  bool get isOpen => entries.any((e) => e.isOpen);

  /// Worked so far today, from the merged day — never from one source alone.
  Duration get worked => workedAt(now);

  /// Total paused, whatever the kind.
  Duration get paused => pausedAt(now);

  /// [worked] measured at an arbitrary instant, so a widget can re-derive it from its own ticking
  /// clock instead of rebuilding this whole object once a second. Only a running stretch changes
  /// between two instants; a closed day returns the same number forever.
  Duration workedAt(DateTime at) =>
      _coveredDuration(entries.where((e) => e.countsAsWorked), at);

  /// [paused] measured at an arbitrary instant — see [workedAt].
  Duration pausedAt(DateTime at) => _coveredDuration(
    entries.where((e) => e.kind != RailKind.work && e.kind != RailKind.unknown),
    at,
  );

  /// True when at least one stretch has not reached the server yet.
  bool get hasPending => entries.any((e) => e.pending);

  /// When the line begins — the first recorded instant of the day, or null on an empty day.
  DateTime? get axisStart => entries.isEmpty ? null : entries.first.start;

  /// When it ends: now while a stretch runs, otherwise the last recorded instant.
  DateTime? get axisEnd => axisEndAt(now);

  /// [axisEnd] measured at an arbitrary instant, for the same reason as [workedAt]: the rail keeps
  /// its own ticking clock, and an axis that stopped at the instant this object was built would
  /// leave a running stretch drawn past its own end (and clamped back to a full-height bar).
  ///
  /// The latest END, not the last-started entry: with two sources an earlier-started stretch can
  /// still be the one running (a phone shift left open under a later, closed totem row), and an
  /// axis that trusted the last start would clip the running band.
  DateTime? axisEndAt(DateTime at) {
    DateTime? end;
    for (final e in entries) {
      final candidate = e.endOr(at);
      if (end == null || candidate.isAfter(end)) end = candidate;
    }
    return end;
  }
}

/// Wall-clock covered by [items] at [at], counting overlapping stretches once.
///
/// Entries come from two sources and may overlap — an offline phone punch and a totem row for the
/// same minutes, an office correction over a phone interval. Summing durations then counts the same
/// minutes twice (the defect that printed 11h09 on a 6h41 day), so merge the spans first.
///
/// A paid pause is deliberately in both [DayRail.workedAt] and [DayRail.pausedAt]: those answer
/// two different questions ("worked" includes paid breaks; "paused" is all break time), not two
/// halves of one total.
Duration _coveredDuration(Iterable<RailEntry> items, DateTime at) {
  final spans = items
      .map((e) => (start: e.start, end: e.endOr(at)))
      .where((s) => !s.end.isBefore(s.start))
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  var total = Duration.zero;
  DateTime? from;
  DateTime? to;
  for (final span in spans) {
    if (from == null) {
      from = span.start;
      to = span.end;
      continue;
    }
    final end = to!;
    if (span.start.isAfter(end)) {
      total += end.difference(from);
      from = span.start;
      to = span.end;
    } else if (span.end.isAfter(end)) {
      to = span.end;
    }
  }
  if (from != null && to != null) total += to.difference(from);
  return total;
}

// ── Builder ───────────────────────────────────────────────────────────────────

const _kIngresso = 'ingresso';
const _kFine = 'fine';
const _kPausa = 'pausa';
const _kRipresa = 'ripresa';

/// Merges the phone's events with the server's rows into one day.
///
/// [localEvents] is the phone's own log for today, chronological, with punches the server
/// permanently refused already removed by the repository (those are named in their own banner —
/// including them would double the day, and nothing will ever retry them). [serverRows] is
/// whatever the server answered, or an empty list when it could not be reached.
///
/// Reconciler-mirrored events (`reconciledOrphanMarker`) are excluded here: they are this phone's
/// local *copy* of the server's active shift, added so the punch control knows what the server
/// already knows. They are not phone punches, the server already holds the row they mirror, and
/// drawing them next to it counts the same day twice.
///
/// Offline is not a degraded mode here: with no server answer the phone's own events still form
/// a complete line for every punch it made. What is lost offline is only what the phone never
/// knew — which is exactly what it cannot know.
DayRail buildDayRail({
  required List<WorkSession> localEvents,
  required List<DayWorkLogEntry> serverRows,
  required DateTime now,
}) {
  final entries = <RailEntry>[];
  final localIds = <String>{};

  // ── The phone's own stretches, reconstructed from its events ────────────────
  //
  // The reconciler's mirrors are dropped before anything else. They carry fresh local ids and a
  // coarser shape (one ingresso/pausa/ripresa from the server's active shift), so neither the
  // clientId join nor the exact-boundary fallback below can absorb them; left in, they draw and
  // count alongside the very server rows they were derived from and the day doubles.
  final events = localEvents.where((e) => e.notes != reconciledOrphanMarker).toList()
    ..sort((a, b) => a.eventTime.compareTo(b.eventTime));

  RailKind? openKind;
  DateTime? openStart;
  bool openPending = false;

  void closeOpen(DateTime at, {bool pending = false}) {
    final kind = openKind;
    final start = openStart;
    if (kind == null || start == null) return;
    // A stretch that ends in the same instant it began is kept, not dropped: two punches in one
    // second still happened, and a rail that silently swallows them reads as a missing punch. Its
    // bar is floored to a few pixels and its printed duration is 0m, which is the truth. Only a
    // stretch that ends *before* it starts (an out-of-order replay) is discarded.
    if (!at.isBefore(start)) {
      entries.add(
        RailEntry(
          kind: kind,
          start: start,
          end: at,
          origin: RailOrigin.phone,
          // Either end unsent means the server does not know this stretch as it stands.
          pending: openPending || pending,
        ),
      );
    }
    openKind = null;
    openStart = null;
    openPending = false;
  }

  void open(RailKind kind, DateTime at, bool pending) {
    openKind = kind;
    openStart = at;
    openPending = pending;
  }

  for (final event in events) {
    localIds.add(event.id);
    final t = event.eventTime;
    switch (event.eventType) {
      case _kIngresso:
        // A second opener without a close in between (a refused punch that is still pending, a
        // queued replay) must not swallow the first: the line simply starts again.
        closeOpen(t);
        open(RailKind.work, t, event.isPendingSync);
      case _kPausa:
        closeOpen(t, pending: event.isPendingSync);
        open(RailKind.breakUndecided, t, event.isPendingSync);
      case _kRipresa:
        closeOpen(t, pending: event.isPendingSync);
        open(RailKind.work, t, event.isPendingSync);
      case _kFine:
        closeOpen(t, pending: event.isPendingSync);
      default:
        // An event type this build does not know is ignored rather than guessed at.
        break;
    }
  }

  // Whatever is still open runs to now.
  if (openKind != null && openStart != null) {
    entries.add(
      RailEntry(
        kind: openKind!,
        start: openStart!,
        end: null,
        origin: RailOrigin.phone,
        pending: openPending,
      ),
    );
  }

  // ── The server's rows this phone did not produce ────────────────────────────
  //
  // Belt and braces for the join below: a row the APP recorded (`sorgente == app`) whose clientId
  // is not one of this phone's events — a server that regrouped or re-keyed the row, a stale
  // local id — still describes a stretch the phone already draws if it starts (and ends) at the
  // same instant, give or take clock rounding. Showing both doubles the day, which is exactly the
  // defect this merge exists to prevent. Deliberately limited to app rows (a totem, QR or office
  // row at the same minute is a different record), one-to-one (two server rows can never both be
  // absorbed by a single phone stretch) and to a tight tolerance.
  final phoneEntries = entries.where((e) => e.origin == RailOrigin.phone).toList();
  final absorbedPhone = <RailEntry>{};

  bool sameStretchAsPhone(DayWorkLogEntry row) {
    if (row.sorgente != 'app') return false;
    final rowIsBreak = _isBreakKind(row.kind);
    for (final p in phoneEntries) {
      if (absorbedPhone.contains(p)) continue;
      final pIsBreak =
          p.kind == RailKind.breakShort ||
          p.kind == RailKind.breakLong ||
          p.kind == RailKind.breakUndecided;
      if (pIsBreak != rowIsBreak) continue;
      if (p.start.difference(row.start).abs() > _sameInstantTolerance) continue;
      final bothOpen = p.end == null && row.end == null;
      final bothClosed =
          p.end != null &&
          row.end != null &&
          p.end!.difference(row.end!).abs() <= _sameInstantTolerance;
      if (!bothOpen && !bothClosed) continue;
      absorbedPhone.add(p);
      return true;
    }
    return false;
  }

  for (final row in serverRows) {
    final clientId = row.clientId;
    if (clientId != null && localIds.contains(clientId)) continue;
    if (sameStretchAsPhone(row)) continue;

    entries.add(
      RailEntry(
        kind: _kindOf(row.kind),
        start: row.start,
        // An open server row runs from its own start to now; a closed one keeps its end.
        end: row.end,
        origin: RailOrigin.server,
        pending: false,
        sorgente: row.sorgente,
      ),
    );
  }

  entries.sort((a, b) => a.start.compareTo(b.start));

  // ── The voids between them ──────────────────────────────────────────────────
  //
  // A void is measured from where the day is actually covered to where the next stretch starts —
  // for an open one that is [now], not "no end". Two cases make this load-bearing: a phone stretch
  // still running while a totem row starts later (the hour between them was recorded by nobody and
  // must be named), and a server row that is open while a later row already exists.
  //
  // `coveredUntil` is the FURTHEST end seen so far, not the previous entry's own end: with two
  // sources sorted by start, a long earlier stretch can cover a later, shorter one, and comparing
  // against the short one would invent a void that has already been recorded.
  final gaps = <RailGap>[];
  if (entries.isNotEmpty) {
    var coveredUntil = entries.first.endOr(now);
    for (var i = 1; i < entries.length; i++) {
      final nextStart = entries[i].start;
      final nextEnd = entries[i].endOr(now);
      if (nextStart.isAfter(coveredUntil)) {
        gaps.add(RailGap(start: coveredUntil, end: nextStart));
        coveredUntil = nextEnd;
      } else if (nextEnd.isAfter(coveredUntil)) {
        coveredUntil = nextEnd;
      }
    }
  }

  return DayRail(entries: entries, gaps: gaps, now: now);
}

/// How far apart two instants may be and still be the same punch (clock rounding, second
/// truncation on one side).
const _sameInstantTolerance = Duration(seconds: 90);

bool _isBreakKind(DayWorkLogKind kind) =>
    kind == DayWorkLogKind.shortBreak ||
    kind == DayWorkLogKind.longBreak ||
    kind == DayWorkLogKind.breakTime;

RailKind _kindOf(DayWorkLogKind kind) => switch (kind) {
  DayWorkLogKind.ordinary => RailKind.work,
  DayWorkLogKind.shortBreak => RailKind.breakShort,
  DayWorkLogKind.longBreak => RailKind.breakLong,
  DayWorkLogKind.breakTime => RailKind.breakUndecided,
  DayWorkLogKind.unknown => RailKind.unknown,
};
