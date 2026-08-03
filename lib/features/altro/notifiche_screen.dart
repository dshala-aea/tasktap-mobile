import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import 'notifiche_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Filter enum
// ══════════════════════════════════════════════════════════════════════════════

enum _NotificaFilter { tutte, nonLette }

extension _FilterLabel on _NotificaFilter {
  String get label => switch (this) {
        _NotificaFilter.tutte => 'Tutte',
        _NotificaFilter.nonLette => 'Non lette',
      };
}

// ══════════════════════════════════════════════════════════════════════════════
// Screen
// ══════════════════════════════════════════════════════════════════════════════

/// Notifiche screen — P4 spec.
///
/// Filter chips → notification list (or EmptyState when empty).
/// "Segna tutte come lette" action in header.
///
/// Data layer: [notificheProvider] — Drift-cached notifications with
/// backend refresh on screen open.
class NotificheScreen extends ConsumerStatefulWidget {
  const NotificheScreen({super.key});

  @override
  ConsumerState<NotificheScreen> createState() => _NotificheScreenState();
}

class _NotificheScreenState extends ConsumerState<NotificheScreen> {
  _NotificaFilter _filter = _NotificaFilter.tutte;

  @override
  void initState() {
    super.initState();
    // Trigger a refresh from the backend when the screen opens.
    // The Drift cache is already loaded by the provider constructor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificheProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(notificheProvider);
    final unread = all.where((n) => !n.letta).length;

    final filtered = switch (_filter) {
      _NotificaFilter.tutte => all,
      _NotificaFilter.nonLette => all.where((n) => !n.letta).toList(),
    };

    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ScreenHeader(
                title: 'Notifiche',
                showBack: true,
                actions: [
                  if (unread > 0)
                    GestureDetector(
                      onTap: () =>
                          ref.read(notificheProvider.notifier).segnaLette(),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Segna tutte',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.BLUE,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Filter chips ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(19, 0, 19, 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _NotificaFilter.values.map((f) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AppChip(
                          label: f.label,
                          active: _filter == f,
                          onTap: () => setState(() => _filter = f),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

            // ── List or Empty ──────────────────────────────────────────────
            if (filtered.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: LucideIcons.bellOff,
                  title: 'Nessuna notifica',
                  body: 'Le notifiche ricevute appariranno qui.',
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final n = filtered[i];
                    return _NotificaRow(
                      notifica: n,
                      isLast: i == filtered.length - 1,
                      onTap: () =>
                          ref.read(notificheProvider.notifier).segnaLetta(n.id),
                    );
                  },
                  childCount: filtered.length,
                ),
              ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Notification row
// ══════════════════════════════════════════════════════════════════════════════

class _NotificaRow extends StatelessWidget {
  const _NotificaRow({
    required this.notifica,
    required this.isLast,
    required this.onTap,
  });

  final AppNotifica notifica;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.BLUE.withAlpha(26),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(LucideIcons.bell, size: 20, color: AppColors.BLUE),
          ),
          if (!notifica.letta)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.BLUE,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.WHITE, width: 1.5),
                ),
              ),
            ),
        ],
      ),
      title: notifica.titolo,
      subtitle: notifica.corpo,
      meta: Text(
        _formatTime(notifica.timestamp),
        style: GoogleFonts.manrope(fontSize: 10, color: AppColors.MUTED),
      ),
      showDivider: !isLast,
      onTap: onTap,
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt.toLocal());
    if (diff.inMinutes < 60) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours} h fa';
    return '${diff.inDays} g fa';
  }
}
