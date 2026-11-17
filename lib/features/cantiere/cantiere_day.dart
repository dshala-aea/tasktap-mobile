// dart format width=100
// lib/features/cantiere/cantiere_day.dart
//
// "Il giorno" — the day's ledger for one cantiere. Reads the offline-durable local punch log
// (`todayCantiereEventsProvider`) rather than the server mirror, so the timeline a technician sees
// at the gate is the same one their phone just recorded, with or without signal. The total comes
// from `cantiereTodayHoursProvider` (closed intervals only); a live session is shown separately by
// `CantiereLiveElapsed`, which ticks only while a session is actually open.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_palette.dart';
import '../timbra/cantiere_timbra_screen.dart'
    show
        cantiereActiveSessionProvider,
        cantiereTodayHoursProvider,
        formatHoursMinutes,
        todayCantiereEventsProvider;
import 'cantiere_design.dart';

/// `HH:MM:SS` for an elapsed duration — the hero / map / close-sheet timer readout.
String formatClock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
}

/// A live "Xh YYm" elapsed label. The timer only exists when this widget is mounted, and callers
/// only mount it for an open session — never on an idle detail screen, where a permanent tick would
/// keep widget tests' `pumpAndSettle` from ever settling.
class CantiereLiveElapsed extends StatefulWidget {
  const CantiereLiveElapsed({super.key, required this.start, this.style, this.clock = false});

  final DateTime start;
  final TextStyle? style;

  /// Render as a `HH:MM:SS` readout (the design's timer) instead of the compact "Xh YYm".
  final bool clock;

  @override
  State<CantiereLiveElapsed> createState() => _CantiereLiveElapsedState();
}

class _CantiereLiveElapsedState extends State<CantiereLiveElapsed> {
  Timer? _timer;
  late Duration _elapsed;

  @override
  void initState() {
    super.initState();
    _elapsed = _now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = _now());
    });
  }

  Duration _now() {
    final d = DateTime.now().difference(widget.start);
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.clock ? formatClock(_elapsed) : formatHoursMinutes(_elapsed),
      style: widget.style,
    );
  }
}

/// The day's ledger: every local ingresso/uscita for [cantiereId], plus the live open session.
/// Rendered as the design's "Il giorno" section: a 17/600 title with the day total in mono on the
/// right, then one ledger card — an 8px dot per event (green done, red live), 11/600 title, 10
/// muted meta, mono time on the right, 1px rules between rows.
class CantiereDayLedger extends ConsumerWidget {
  const CantiereDayLedger({super.key, required this.cantiereId});

  final String cantiereId;

  static String _hm(DateTime t) => DateFormat('HH:mm').format(t.toLocal());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events =
        (ref.watch(todayCantiereEventsProvider).value ?? [])
            .where((e) => e.cantiereId == cantiereId)
            .toList()
          ..sort((a, b) => a.eventTime.compareTo(b.eventTime));
    final active = ref.watch(cantiereActiveSessionProvider);
    final activeHere = active?.cantiereId == cantiereId;
    final closed = ref.watch(cantiereTodayHoursProvider(cantiereId));
    final empty = events.isEmpty && !activeHere;

    final rows = <Widget>[
      for (final e in events)
        CantiereLedgerRow(
          done: true,
          title: e.eventType == 'ingresso' ? 'Ingresso in cantiere' : 'Uscita dal cantiere',
          meta: [
            if (e.description?.trim().isNotEmpty ?? false) e.description!.trim(),
            if (e.isPendingSync) 'Da inviare',
          ].join(' · '),
          time: _hm(e.eventTime),
        ),
      if (activeHere)
        CantiereLedgerRow(
          done: false,
          title: 'Sessione in corso',
          meta: 'Sessione aperta alle ${_hm(active!.startTime)}',
          time: _hm(active.startTime),
        ),
    ];

    return CantiereSection(
      title: 'Il giorno',
      noteWidget: activeHere
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CantiereLiveElapsed(
                  start: active!.startTime,
                  style: cantiereMono(context, 8.5, letterSpacing: 0.51),
                ),
                Text(' IN CORSO', style: cantiereMono(context, 8.5, letterSpacing: 0.51)),
              ],
            )
          : closed > Duration.zero
          ? Text(
              formatHoursMinutes(closed).toUpperCase(),
              style: cantiereMono(context, 8.5, letterSpacing: 0.51),
            )
          : null,
      child: CantiereCard(
        padding: empty
            ? const EdgeInsets.all(14)
            : const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: empty
            ? Text(
                'Nessuna timbratura oggi.',
                style: cantiereBody(context, 11, color: context.colors.inkMuted),
              )
            : Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const CantiereRule(),
                    rows[i],
                  ],
                ],
              ),
      ),
    );
  }
}

/// One ledger row: 8px status dot, 11/600 title, 10 muted meta, mono time on the right.
class CantiereLedgerRow extends StatelessWidget {
  const CantiereLedgerRow({
    super.key,
    required this.done,
    required this.title,
    required this.meta,
    required this.time,
  });

  final bool done;
  final String title;
  final String meta;
  final String time;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dot = done ? c.green : c.accentInk;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: DecoratedBox(
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              child: const SizedBox(width: 8, height: 8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: cantiereBody(context, 11, weight: FontWeight.w600)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(meta, style: cantiereBody(context, 10, color: c.inkMuted, height: 1.35)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(time, style: cantiereMono(context, 8.5)),
        ],
      ),
    );
  }
}
