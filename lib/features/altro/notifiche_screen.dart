import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/notification_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/widgets/widgets.dart';
import 'notifiche_provider.dart';
import 'package:tasktap_mobile/core/widgets/app_tappable.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

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

  /// Navigates to whatever the notification is about, if it names something we can open.
  ///
  /// Silently does nothing when the pair is absent or the type is one we have no screen for —
  /// the notification has still been marked read, which is the part the technician asked for by
  /// tapping. Bouncing them to an error for a notification that simply has no destination would
  /// be worse than staying put.
  void _openRelatedEntity(BuildContext context, AppNotifica n) {
    final type = n.relatedEntityType;
    final id = n.relatedEntityId;
    if (type == null || id == null) return;

    final route = DeepLinkIntent(entityType: type, entityId: id).resolveRoute();
    if (route != null) context.push(route);
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
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ScreenHeader(
                title: 'Notifiche',
                showBack: true,
                actions: [
                  if (unread > 0)
                    // A bare text action, so the splash is the only thing that confirms the
                    // press at all — the list it clears is below the fold on a full inbox.
                    AppTappable(
                      onTap: () => ref.read(notificheProvider.notifier).segnaLette(),
                      borderRadius: BorderRadius.circular(6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      child: Text(
                        'Segna tutte',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.colors.blue,
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
                delegate: SliverChildBuilderDelegate((context, i) {
                  final n = filtered[i];
                  return _NotificaRow(
                    notifica: n,
                    isLast: i == filtered.length - 1,
                    // Marking read was the only thing a tap did. The row already carried
                    // relatedEntityType/relatedEntityId — the same pair a push tap resolves
                    // through DeepLinkIntent — so opening the notification centre and tapping
                    // an item left the technician to go and find the job themselves.
                    onTap: () {
                      ref.read(notificheProvider.notifier).segnaLetta(n.id);
                      _openRelatedEntity(context, n);
                    },
                  );
                }, childCount: filtered.length),
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
  const _NotificaRow({required this.notifica, required this.isLast, required this.onTap});

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
              color: context.colors.blue.withAlpha(26),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(LucideIcons.bell, size: 20, color: context.colors.blue),
          ),
          if (!notifica.letta)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: context.colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.colors.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
      title: notifica.titolo,
      subtitle: notifica.corpo,
      meta: Text(
        _formatTime(notifica.timestamp),
        style: GoogleFonts.manrope(fontSize: 10, color: context.colors.inkMuted),
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
