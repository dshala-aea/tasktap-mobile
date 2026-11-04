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
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/widgets.dart';
import '../timbra/cantiere_timbra_screen.dart'
    show
        cantiereActiveSessionProvider,
        cantiereTodayHoursProvider,
        formatHoursMinutes,
        todayCantiereEventsProvider;

/// A live "Xh YYm" elapsed label. The timer only exists when this widget is mounted, and callers
/// only mount it for an open session — never on an idle detail screen, where a permanent tick would
/// keep widget tests' `pumpAndSettle` from ever settling.
class CantiereLiveElapsed extends StatefulWidget {
  const CantiereLiveElapsed({super.key, required this.start, this.style});

  final DateTime start;
  final TextStyle? style;

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
    return Text(formatHoursMinutes(_elapsed), style: widget.style);
  }
}

/// The day's ledger: every local ingresso/uscita for [cantiereId], plus the live open session.
class CantiereDayLedger extends ConsumerWidget {
  const CantiereDayLedger({super.key, required this.cantiereId});

  final String cantiereId;

  static String _hm(DateTime t) => DateFormat('HH:mm').format(t.toLocal());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events =
        (ref.watch(todayCantiereEventsProvider).valueOrNull ?? [])
            .where((e) => e.cantiereId == cantiereId)
            .toList()
          ..sort((a, b) => a.eventTime.compareTo(b.eventTime));
    final active = ref.watch(cantiereActiveSessionProvider);
    final activeHere = active?.cantiereId == cantiereId;
    final closed = ref.watch(cantiereTodayHoursProvider(cantiereId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionTitle(title: 'Il giorno')),
            if (activeHere) ...[
              CantiereLiveElapsed(
                start: active!.startTime,
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'in corso',
                style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
              ),
            ] else if (closed > Duration.zero)
              Text(
                formatHoursMinutes(closed),
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.colors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AppCard(
          padding: events.isEmpty && !activeHere
              ? const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md)
              : EdgeInsets.zero,
          child: events.isEmpty && !activeHere
              ? Text(
                  'Nessuna timbratura oggi.',
                  style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
                )
              : Column(
                  children: [
                    for (var i = 0; i < events.length; i++)
                      ListRow(
                        leading: Icon(
                          events[i].eventType == 'ingresso'
                              ? LucideIcons.logIn
                              : LucideIcons.logOut,
                          size: 18,
                          color: context.colors.ink,
                        ),
                        title: events[i].eventType == 'ingresso' ? 'Ingresso' : 'Uscita',
                        subtitle: events[i].description?.trim().isEmpty ?? true
                            ? null
                            : events[i].description!.trim(),
                        meta: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (events[i].isPendingSync) ...[
                              const AppBadge(label: 'Da inviare', small: true),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              _hm(events[i].eventTime),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: context.colors.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        showDivider: i != events.length - 1 || activeHere,
                      ),
                    if (activeHere)
                      ListRow(
                        leading: Icon(LucideIcons.timer, size: 18, color: context.colors.ink),
                        title: 'In corso',
                        subtitle: 'Sessione aperta alle ${_hm(active!.startTime)}',
                        meta: CantiereLiveElapsed(
                          start: active.startTime,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
