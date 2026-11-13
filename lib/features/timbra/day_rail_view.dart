// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// DayRailView — "La giornata in linea"
//
// The day drawn as one continuous time axis: a hairline spine running down the left of the field,
// a thick carbon bar for every stretch actually worked, a hollow amber bar for every pause, and
// the spine left as a dashed hairline wherever the day has nothing recorded at all. The reader
// does not have to subtract anything: each stretch and each void carries its own measured
// duration, printed in mono beside its name, and the bar lengths are proportional to the same
// axis they sit on.
//
// Why the labels are laid out independently of the bands: two punches five minutes apart produce
// two bars eight pixels apart, and their labels cannot both sit at their anchors without
// colliding. The bands keep the true geometry — they ARE the measurement — while the labels are
// pushed down only as far as they must be, still printing exact clock times. When even that does
// not fit, every label is distributed evenly and the printed times remain the authority. The
// diagram is a diagram; the numbers are the truth, and they are always visible.
//
// See day_rail.dart for how the two sources (this phone's events, the server's rows) become the
// list this draws.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_rack.dart' show AppRack;
import '../../core/theme/app_spacing.dart' show AppSpacing;
import '../../core/time/business_time.dart' show BusinessTime;
import '../../core/time/business_time_providers.dart' show businessTimeProvider;
import '../dashboard/active_trackers_provider.dart' show nowProvider;
import 'day_rail.dart';

/// Height the rail falls back to when its parent hands it an unbounded box (it never should — both
/// callers give it an `Expanded` or a fixed `SizedBox` — but a `LayoutBuilder` must not divide by an
/// infinite extent either way).
const double _kFallbackHeight = 320;

/// Left column reserved for the hour marks, then the spine, then the labels. The spine sits just
/// outside the gutter so the whole day reads as one ruled instrument rather than a list with
/// decoration beside it.
const double _kSpineX = 54;
const double _kLabelLeft = 66;
const double _kPadTop = 14;
const double _kPadBottom = 12;
const double _kBandHalfWidth = 3;

/// Label box heights at text scale 1, used to decide how far a label must be pushed down. They are
/// scaled by the ambient text scaler before use: a technician running the system font at 1.3
/// (common, and not optional at 60+) gets taller labels, not a clipped line.
///
/// The entry box holds a title and up to two lines of detail. Two, not one: the detail is
/// `08:00–17:30 · questo telefono · in attesa`, and at 360dp / 1.3 the provenance — the whole
/// reason this rail exists — was the part the ellipsis ate. A void's label is a single line and
/// nothing else, so it keeps its own, smaller box.
const double _kEntryLabelH = 40;
const double _kGapLabelH = 16;
const double _kLabelGap = 4;

/// What the two sources of the day actually said — which decides what an empty rail may claim.
///
/// The three cases are not degrees of the same failure. A complete day may say "nothing happened
/// today". A day whose server did not answer may only say what this phone knows, because a totem
/// punch exists somewhere this screen cannot read. A day whose *own phone* could not be read is not
/// partly known at all: it is unknown, and it must not invite a punch into a day nobody has seen.
enum DayCoverage { complete, phoneOnly, unknown }

class DayRailView extends ConsumerStatefulWidget {
  const DayRailView({super.key, required this.day, this.coverage = DayCoverage.complete});

  final DayRail day;

  /// What this rail may claim when it has nothing to draw. An empty rail is a statement about the
  /// day ("nothing happened today"), and that statement is only true when both sources answered —
  /// so the callers say which of them did. See [DayCoverage].
  final DayCoverage coverage;

  @override
  ConsumerState<DayRailView> createState() => _DayRailViewState();
}

class _DayRailViewState extends ConsumerState<DayRailView> with SingleTickerProviderStateMixin {
  /// The one authored motion moment on this screen: the dot at the moving end of a running stretch.
  /// It is the only thing on the page that says, without a word, that the number above is still
  /// counting.
  late final AnimationController _pulse;
  bool _reduced = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (!_started) {
      _started = true;
      _syncPulse();
    }
  }

  @override
  void didUpdateWidget(covariant DayRailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.day.isOpen && !_reduced) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final colors = context.colors;
    if (day.isEmpty) {
      return _RailField(child: _RailEmpty(coverage: widget.coverage));
    }

    final bt = ref.watch(businessTimeProvider);
    // A closed day cannot move, so its own build instant is used rather than the ticking clock;
    // an open one re-derives every second from the shared ticker instead of rebuilding the whole
    // screen (which is what watching it in TimbraScreen would do).
    final ticking = ref.watch(nowProvider).value;
    final now = day.isOpen ? (ticking ?? DateTime.now()) : day.now;

    // Labels grow with the system font. Their box height is what the push-down maths measures, so
    // an unscaled height here is a clipped second line on any phone set above 1.0.
    final textScale = MediaQuery.textScalerOf(context);
    final entryLabelH = textScale.scale(_kEntryLabelH);
    final gapLabelH = textScale.scale(_kGapLabelH);

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : _kFallbackHeight;
        final width = constraints.maxWidth;

        final bottom = math.max(_kPadTop + 40, height - _kPadBottom);
        // The axis ends at the tick the bands are drawn to, not at the instant the provider built
        // this DayRail: an open stretch drawn past its own axis is clamped into a full-height bar.
        final axis = _Axis(
          start: day.axisStart!,
          end: day.axisEndAt(now)!,
          top: _kPadTop,
          bottom: bottom,
        );

        final bands = <_Band>[];
        final voids = <_Void>[];
        final nodes = <_Node>[];
        final labels = <_LabelSpec>[];

        for (final entry in day.entries) {
          final y0 = axis.y(entry.start);
          final y1 = axis.y(entry.endOr(now));
          // A ten-minute stretch on an eight-hour day is under a pixel tall; drawn at its true
          // height it would vanish, and a vanished stretch reads as a missing one. The bar is
          // floored so it stays visible, and its printed duration carries the real measurement.
          final h = math.max(y1 - y0, 4.0);
          bands.add(_Band(top: y0, height: h, kind: entry.kind, pending: entry.pending));
          nodes.add(_Node(y: y0, colour: _bandInk(entry.kind, colors), open: false));
          if (!entry.isOpen) {
            nodes.add(_Node(y: y0 + h, colour: colors.borderLight, open: false));
          }
          labels.add(
            _LabelSpec(
              anchor: y0 + h / 2,
              height: entryLabelH,
              title: _titleOf(entry),
              detail: '${_rangeOf(entry, bt, now)} · ${_originOf(entry)}',
              duration: _fmtDuration(entry.durationAt(now)),
              tone: entry.pending
                  ? colors.amberInk
                  : (entry.countsAsWorked ? colors.ink : colors.inkMuted),
              detailTone: entry.pending ? colors.amberInk : colors.inkMuted,
              isVoid: false,
            ),
          );
        }

        for (final gap in day.gaps) {
          final y0 = axis.y(gap.start);
          final y1 = axis.y(gap.end);
          final h = math.max(y1 - y0, 2.0);
          voids.add(_Void(top: y0, height: h));
          labels.add(
            _LabelSpec(
              anchor: y0 + h / 2,
              height: gapLabelH,
              title: 'Non timbrato',
              detail: '',
              duration: _fmtDuration(gap.duration),
              tone: colors.inkMuted,
              detailTone: colors.inkMuted,
              isVoid: true,
            ),
          );
        }

        final ticks = _tickMarks(bt, day.axisStart!, day.axisEndAt(now)!, axis);
        labels.sort((a, b) => a.anchor.compareTo(b.anchor));
        final labelYs = _layoutLabels(labels, height);

        return _RailField(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      painter: _RailPainter(
                        bands: bands,
                        voids: voids,
                        nodes: nodes,
                        ticks: ticks,
                        top: _kPadTop,
                        bottom: bottom,
                        ink: colors.ink,
                        amber: colors.amber,
                        amberInk: colors.amberInk,
                        rule: colors.borderLight,
                        muted: colors.inkMuted,
                        tickInk: colors.inkMuted,
                        live: colors.accentInk,
                        liveY: day.isOpen ? axis.y(now) : null,
                        pulse: _pulse.value,
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < labels.length; i++)
                  Positioned(
                    left: _kLabelLeft,
                    top: labelYs[i],
                    // Inset from the field's own hairline. At right: 0 the right-aligned duration
                    // ended 2dp from the border and read as touching the frame in every state.
                    right: AppSpacing.md,
                    child: _RailLabel(spec: labels[i]),
                  ),
                // The gutter reads bottom-to-top like a clock face's minute track: drawn last so it
                // is never covered by a label.
                for (final tick in ticks)
                  Positioned(
                    left: 0,
                    width: _kSpineX - 10,
                    top: tick.y - 6,
                    child: Text(
                      tick.label,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'IBM Plex Mono',
                        fontSize: 9,
                        height: 1.2,
                        letterSpacing: 0.2,
                        color: colors.inkMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Label layout
// ══════════════════════════════════════════════════════════════════════════════

/// Pushes each label down from its anchor only as far as the previous label forces it, then falls
/// back to an even distribution when even that does not fit — see this file's header for why the
/// printed times, not the label position, are the authority.
List<double> _layoutLabels(List<_LabelSpec> labels, double available) {
  if (labels.isEmpty) return const [];

  final ys = List<double>.filled(labels.length, 0);
  var cursor = 0.0;
  for (var i = 0; i < labels.length; i++) {
    final wanted = labels[i].anchor - labels[i].height / 2;
    ys[i] = math.max(wanted, cursor);
    cursor = ys[i] + labels[i].height + _kLabelGap;
  }

  final total = cursor - _kLabelGap;
  if (total <= available - _kPadBottom || labels.length == 1) return ys;

  // Even distribution: guaranteed inside the box, and no more of a lie than the push-down was.
  final span = math.max(available - labels[0].height, 0.0);
  for (var i = 0; i < labels.length; i++) {
    ys[i] = math.max(0, span * i / (labels.length - 1));
  }
  return ys;
}

// ══════════════════════════════════════════════════════════════════════════════
// One label
// ══════════════════════════════════════════════════════════════════════════════

class _LabelSpec {
  const _LabelSpec({
    required this.anchor,
    required this.height,
    required this.title,
    required this.detail,
    required this.duration,
    required this.tone,
    required this.detailTone,
    required this.isVoid,
  });

  final double anchor;
  final double height;
  final String title;
  final String detail;
  final String duration;
  final Color tone;
  final Color detailTone;
  final bool isVoid;
}

class _RailLabel extends StatelessWidget {
  const _RailLabel({required this.spec});

  final _LabelSpec spec;

  @override
  Widget build(BuildContext context) {
    if (spec.isVoid) {
      return SizedBox(
        height: spec.height,
        child: Row(
          children: [
            Expanded(
              child: Text(
                spec.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Archivo Narrow',
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: spec.tone,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              spec.duration,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'IBM Plex Mono',
                fontSize: 10.5,
                height: 1.1,
                color: spec.tone,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: spec.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  spec.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Archivo Narrow',
                    fontSize: 13,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: spec.tone,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'IBM Plex Mono',
                    fontSize: 9.5,
                    height: 1.15,
                    letterSpacing: 0.1,
                    color: spec.detailTone,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              spec.duration,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'IBM Plex Mono',
                fontSize: 11,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: spec.tone,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Empty day
// ══════════════════════════════════════════════════════════════════════════════

/// The rail's own field: the sheet the instrument is printed on.
///
/// The screen's ground is paper; the day is a separate sheet of it, one hairline and a 2px corner
/// away from the ground. Without it the spine and the bars float on the same tone as the head above
/// them, and the empty state reads as text that happens to be centred rather than as a page that is
/// blank. It is the only filled surface on this screen, which is what makes the drawn day read as
/// the object.
class _RailField extends StatelessWidget {
  const _RailField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRack.freeShape,
        border: Border.all(color: context.colors.borderLight),
      ),
      child: child,
    );
  }
}

/// An empty day is not an error and must not look like one: the rail is simply blank paper with
/// the one thing the technician can do about it said plainly. No spinner, no dashed placeholder
/// frame, nothing to misread as a failure.
class _RailEmpty extends StatelessWidget {
  const _RailEmpty({required this.coverage});

  final DayCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (coverage) {
      DayCoverage.complete => (
        'Nessuna timbratura oggi',
        'Timbra per far partire la giornata: qui comparirà minuto per minuto.',
      ),
      // "oggi" is a claim about the day; until the server has answered, the honest subject is
      // this phone — the only source that spoke.
      DayCoverage.phoneOnly => (
        'Nessuna timbratura su questo telefono',
        'La giornata del server non è raggiungibile: le timbrature del totem o di un '
            'altro dispositivo potrebbero mancare.',
      ),
      // Nothing is known, so nothing about the day is claimed: no "timbra per far partire la
      // giornata", no invitation to punch into a day this phone could not read. The wording stops
      // at what is true of the rail itself rather than ordering the technician around — the punch
      // deck is the server's to refuse or allow, not this sentence's.
      DayCoverage.unknown => (
        'Timbrature non leggibili',
        'Questo telefono non riesce a leggere le timbrature di oggi: il riepilogo qui non è '
            'completo. Chiudi e riapri l\'app.',
      ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Archivo Narrow',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.colors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 12,
                height: 1.35,
                color: context.colors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Geometry
// ══════════════════════════════════════════════════════════════════════════════

/// The day's time axis. Proportional, from the first recorded instant to the last (or to now while
/// anything is open) — not to the calendar day, because a technician who punched in at 07:40 and
/// out at 17:10 should not see four-fifths of their screen spent on hours they never worked.
class _Axis {
  _Axis({required this.start, required this.end, required this.top, required this.bottom})
    : _spanMs = math.max(
        end.difference(start).inMilliseconds,
        5 * 60 * 1000, // a day shorter than five minutes has no axis worth drawing
      );

  final DateTime start;
  final DateTime end;
  final double top;
  final double bottom;
  final int _spanMs;

  double y(DateTime t) {
    final offset = t.difference(start).inMilliseconds;
    final fraction = (offset / _spanMs).clamp(0.0, 1.0);
    return top + fraction * (bottom - top);
  }
}

class _TickMark {
  const _TickMark({required this.y, required this.label});
  final double y;
  final String label;
}

/// Half-hour marks for a short day, hour marks otherwise. Boundaries are found by formatting the
/// instant in the business zone and rounding to the next multiple — no timezone arithmetic, so a
/// DST shift moves the printed labels without moving the maths.
List<_TickMark> _tickMarks(BusinessTime bt, DateTime from, DateTime to, _Axis axis) {
  final span = to.difference(from);
  final stepMin = span <= const Duration(hours: 3) ? 30 : 60;

  var t = from.subtract(
    Duration(seconds: from.second, milliseconds: from.millisecond, microseconds: from.microsecond),
  );
  final minute = int.tryParse(bt.formatInZone(t, 'mm')) ?? 0;
  final toNext = (stepMin - (minute % stepMin)) % stepMin;
  t = t.add(Duration(minutes: toNext));

  final marks = <_TickMark>[];
  while (t.isBefore(to) && marks.length < 48) {
    marks.add(_TickMark(y: axis.y(t), label: bt.formatInZone(t, 'HH:mm')));
    t = t.add(Duration(minutes: stepMin));
  }
  return marks;
}

// ══════════════════════════════════════════════════════════════════════════════
// Painter
// ══════════════════════════════════════════════════════════════════════════════

class _Band {
  const _Band({required this.top, required this.height, required this.kind, required this.pending});
  final double top;
  final double height;
  final RailKind kind;
  final bool pending;
}

class _Void {
  const _Void({required this.top, required this.height});
  final double top;
  final double height;
}

class _Node {
  const _Node({required this.y, required this.colour, required this.open});
  final double y;
  final Color colour;
  final bool open;
}

Color _bandInk(RailKind kind, AppPalette colors) => switch (kind) {
  RailKind.work => colors.ink,
  RailKind.unknown => colors.ink,
  _ => colors.amber,
};

class _RailPainter extends CustomPainter {
  const _RailPainter({
    required this.bands,
    required this.voids,
    required this.nodes,
    required this.ticks,
    required this.top,
    required this.bottom,
    required this.ink,
    required this.amber,
    required this.amberInk,
    required this.rule,
    required this.muted,
    required this.tickInk,
    required this.live,
    required this.liveY,
    required this.pulse,
  });

  final List<_Band> bands;
  final List<_Void> voids;
  final List<_Node> nodes;
  final List<_TickMark> ticks;
  final double top;
  final double bottom;
  final Color ink;

  /// The In-lavorazione amber as a FILL — the solid bar of a paid pause, which is part of the day
  /// and counted in the total. Not the text token: a paid pause is the one break that reads as
  /// occupied time, and `amberInk` (darkened to clear 4.5:1 as a glyph) would darken it towards the
  /// carbon of a worked stretch until the two bars were only distinguishable by width.
  final Color amber;

  /// The same family as a HAIRLINE: the hollow outline of an unpaid or not-yet-frozen break. It is
  /// a 1.2px stroke on the Sheet field, so it takes the ink value that is legible there.
  final Color amberInk;
  final Color rule;
  final Color muted;
  final Color tickInk;
  final Color live;
  final double? liveY;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final spinePaint = Paint()
      ..color = rule
      ..strokeWidth = 1;

    // The spine: one unbroken hairline for the whole span. Everything else either thickens it
    // (worked), hollows it out (paused) or dashes it over it (nothing recorded).
    canvas.drawLine(Offset(_kSpineX, top), Offset(_kSpineX, bottom), spinePaint);

    for (final tick in ticks) {
      canvas.drawLine(
        Offset(_kSpineX - 7, tick.y),
        Offset(_kSpineX, tick.y),
        Paint()
          ..color = tickInk.withAlpha(90)
          ..strokeWidth = 1,
      );
    }

    for (final void_ in voids) {
      _drawDashes(
        canvas,
        Offset(_kSpineX, void_.top),
        Offset(_kSpineX, void_.top + void_.height),
        Paint()
          ..color = muted.withAlpha(120)
          ..strokeWidth = 1.4,
      );
    }

    for (final band in bands) {
      _drawBand(canvas, band);
    }

    for (final node in nodes) {
      canvas.drawCircle(
        Offset(_kSpineX, node.y),
        1.9,
        Paint()..color = node.colour.withAlpha(node.open ? 255 : 200),
      );
    }

    final nowY = liveY;
    if (nowY != null) {
      final eased = pulse;
      canvas.drawCircle(
        Offset(_kSpineX, nowY),
        3.4 + 3.4 * eased,
        Paint()..color = live.withAlpha((70 * (1 - eased)).round().clamp(0, 255)),
      );
      canvas.drawCircle(Offset(_kSpineX, nowY), 3.4, Paint()..color = live);
    }
  }

  void _drawBand(Canvas canvas, _Band band) {
    final rect = Rect.fromLTWH(
      _kSpineX - _kBandHalfWidth,
      band.top,
      _kBandHalfWidth * 2,
      band.height,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(1.5));

    switch (band.kind) {
      case RailKind.work:
      case RailKind.unknown:
        canvas.drawRRect(rrect, Paint()..color = ink.withAlpha(band.pending ? 110 : 255));
      case RailKind.breakShort:
        // Paid: a solid amber bar — it is part of the day, counted in the total.
        canvas.drawRRect(rrect, Paint()..color = amber.withAlpha(band.pending ? 120 : 255));
      case RailKind.breakLong:
      case RailKind.breakUndecided:
        // Unpaid, or not yet known: hollow. The day is interrupted, and the total does not count
        // these minutes — the bar's emptiness says exactly that.
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = amberInk.withAlpha(band.pending ? 130 : 235)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
    }
  }

  void _drawDashes(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 2.0;
    const gap = 2.5;
    final total = (to - from).distance;
    if (total <= 0) return;
    final dir = (to - from) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = math.min(travelled + dash, total);
      canvas.drawLine(from + dir * travelled, from + dir * end, paint);
      travelled = end + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _RailPainter old) =>
      old.pulse != pulse ||
      old.bands != bands ||
      old.voids != voids ||
      old.nodes != nodes ||
      old.ticks != ticks ||
      old.bottom != bottom ||
      old.liveY != liveY ||
      old.ink != ink ||
      old.amber != amber ||
      old.amberInk != amberInk;
}

// ══════════════════════════════════════════════════════════════════════════════
// Copy
// ══════════════════════════════════════════════════════════════════════════════

String _titleOf(RailEntry entry) => switch (entry.kind) {
  RailKind.work => 'Turno',
  RailKind.unknown => 'Turno',
  RailKind.breakShort => 'Pausa',
  // A `Break` row whose kind is not frozen yet — and every legacy one — is unpaid until closed,
  // so it is named for what it will be read as, not for what it might become.
  RailKind.breakUndecided => 'Pausa',
  RailKind.breakLong => 'Pranzo',
};

String _rangeOf(RailEntry entry, BusinessTime bt, DateTime now) {
  final start = bt.formatInZone(entry.start, 'HH:mm');
  if (entry.isOpen) return 'dal $start';
  final end = bt.formatInZone(entry.endOr(now), 'HH:mm');
  return '$start–$end';
}

/// Where the stretch came from, in the technician's own words. This is the whole point of the
/// merge: a row the office corrected and a row this phone made must not read the same.
String _originOf(RailEntry entry) {
  if (entry.origin == RailOrigin.phone) {
    return entry.pending ? 'questo telefono · in attesa' : 'questo telefono';
  }
  return railSorgenteLabel(entry.sorgente);
}

/// The origin word for a server row's `sorgente` key. Anything unknown — null, or a source a newer
/// server added — is the neutral "server": the rail never throws on, or mislabels, a source it
/// has not met.
@visibleForTesting
String railSorgenteLabel(String? sorgente) => switch (sorgente) {
  'totem' => 'totem',
  'qr' => 'QR',
  'app' => 'altro dispositivo',
  'manuale' => 'ufficio',
  'trasferta' => 'trasferta',
  'smartworking' => 'smart working',
  _ => 'server',
};

/// `1h 12m`, `34m`, `4m` — never `0h 12m`, because a pause of a quarter of an hour is not a
/// truncated hour.
String _fmtDuration(Duration d) {
  final safe = d.isNegative ? Duration.zero : d;
  final h = safe.inHours;
  final m = safe.inMinutes.remainder(60);
  if (h == 0) return '${m}m';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}
