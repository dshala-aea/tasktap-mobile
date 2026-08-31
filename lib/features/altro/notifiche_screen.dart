import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_vetro_palette.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/widgets/widgets.dart';
import 'notifiche_provider.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

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
    final hasError = ref.watch(notificheHasErrorProvider);
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
                    // ConstrainedBox guarantees the 44dp touch-target floor the padding alone
                    // (sm/md around 12px text) falls short of — same guarantee HeaderIconBtn
                    // gives its own action buttons.
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: AppTappable(
                        onTap: () =>
                            ref.read(notificheProvider.notifier).segnaLette(),
                        borderRadius: BorderRadius.circular(6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.md,
                        ),
                        child: Text(
                          'Segna tutte',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            // The header is a flipping ScreenHeader now, not a permanently-dark
                            // CHARCOAL plate — fixed white here was unreadable (white-on-white) in
                            // light mode. context.vetro.tint matches every other tinted header
                            // action in the app and flips correctly with the theme.
                            color: context.vetro.tint,
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  0,
                  AppSpacing.pagePadding,
                  AppSpacing.md,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _NotificaFilter.values.map((f) {
                      return Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
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
            // hasError only overrides the empty state — a failed refresh keeps whatever the
            // Drift cache already had, so a non-empty `all` here means the cache is still good
            // even if the latest refresh() didn't reach the server.
            if (filtered.isEmpty && hasError)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: LucideIcons.wifiOff,
                  title: 'Impossibile caricare le notifiche',
                  body: 'Controlla la connessione e riprova.',
                  action: AppButton(
                    label: 'Riprova',
                    size: AppButtonSize.sm,
                    fullWidth: false,
                    onPressed: () =>
                        ref.read(notificheProvider.notifier).refresh(),
                  ),
                ),
              )
            else if (filtered.isEmpty)
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

            SliverPadding(
              padding: EdgeInsets.only(bottom: context.navClearance),
            ),
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
              color: context.colors.blue.withAlpha(26),
              borderRadius: AppRack.insetShape,
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
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          color: context.colors.inkMuted,
        ),
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
