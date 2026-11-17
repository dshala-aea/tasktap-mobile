import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_rack.dart';
import '../../core/widgets/widgets.dart';
import '../calendario/views/lista_view.dart';
import 'dashboard_providers.dart';

/// Past schedules, newest first, grouped by day.
///
/// Reuses [ListaView] (the Calendario list's own grouped rows) rather than duplicating its row
/// rendering. The only differences are the reversed day order, history-specific empty copy, and a
/// full-screen bottom inset instead of the shell's nav clearance.
class StoricoScreen extends ConsumerWidget {
  const StoricoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final past = ref.watch(pastSchedulesProvider);
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Storico', showBack: true),
            Expanded(
              child: past.when(
                data: (schedules) => ListaView(
                  schedules: schedules,
                  onTapTicket: (id) =>
                      context.push(AppRoutes.ticketDetailPath(id)),
                  reverseDays: true,
                  emptyTitle: 'Nessuno storico',
                  emptyBody: 'Gli interventi passati appariranno qui.',
                  bottomPadding: context.fabSafeBottom,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const EmptyState(
                  icon: LucideIcons.calendarX,
                  title: 'Storico non disponibile',
                  body: 'Impossibile leggere gli interventi passati.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
