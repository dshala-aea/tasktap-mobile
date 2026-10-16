import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import '../../core/widgets/widgets.dart';
import '../../data/settings/notification_preferences_api_client.dart';
import '../../data/sync/connectivity_provider.dart';
import 'notification_preferences_provider.dart';

/// "Preferenze notifiche" — one switch per notification type the user may mute.
///
/// Reached from Impostazioni, behind `sistema.notification.read`. The coarse channel and category
/// switches there (push, email, Interventi, ...) stay: they are a different server route and a
/// different question ("how" and "which family" versus "exactly which event").
///
/// ## Online-only
///
/// There is no local copy of these switches. Offline, the screen says so instead of drawing
/// switches whose state nobody can vouch for, and it does not even start the fetch.
///
/// ## Optimistic toggle
///
/// A switch flips at once and is written in the background. If the write fails it is put back and a
/// toast says why — the screen never keeps showing a state the server does not hold. A row ignores
/// further taps while its own write is in flight.
///
/// Whole rows are tappable (the switch itself is already 44 pt): the screen is used gloved and
/// one-handed, where hitting a 38 pt track is the wrong thing to ask of anyone.
class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Preferenze notifiche', showBack: true),
            Expanded(child: online ? const _OnlineBody() : const _OfflineBody()),
          ],
        ),
      ),
    );
  }
}

class _OfflineBody extends StatelessWidget {
  const _OfflineBody();

  @override
  Widget build(BuildContext context) {
    return const UnavailableState(
      icon: LucideIcons.wifiOff,
      titolo: 'Preferenze non disponibili offline',
      motivo:
          'Le preferenze di notifica si leggono e si salvano sul server: riprova quando torni '
          'online.',
    );
  }
}

class _OnlineBody extends ConsumerWidget {
  const _OnlineBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationPreferencesProvider);
    final notifier = ref.read(notificationPreferencesProvider.notifier);

    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = state.error;
    if (error != null && state.items.isEmpty) {
      return UnavailableState(
        icon: error.offline ? LucideIcons.wifiOff : LucideIcons.alertTriangle,
        titolo: error.offline
            ? 'Preferenze non disponibili offline'
            : 'Impossibile caricare le preferenze',
        motivo: error.message,
        action: AppButton(label: 'Riprova', onPressed: notifier.load),
      );
    }

    final groups = groupPreferences(state.items);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.sm,
              AppSpacing.pagePadding,
              0,
            ),
            child: Text(
              'Scegli quali avvisi ricevere. Gli avvisi obbligatori, come le scadenze di licenza, '
              'non compaiono qui e arrivano sempre.',
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 12,
                height: 1.4,
                color: context.colors.inkMuted,
              ),
            ),
          ),
        ),
        for (final (group, rows) in groups) ...[
          SliverToBoxAdapter(child: _SectionTitle(title: group.title)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      _PreferenceRow(
                        pref: rows[i],
                        busy: state.pending.contains(rows[i].type),
                        showDivider: i < rows.length - 1,
                        onToggle: () async {
                          final message = await notifier.toggle(rows[i].type);
                          if (message != null && context.mounted) {
                            showAppToast(context, message: message, tone: ToastTone.error);
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.lg,
        AppSpacing.pagePadding,
        AppSpacing.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Archivo',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: context.colors.inkMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.pref,
    required this.busy,
    required this.showDivider,
    required this.onToggle,
  });

  final NotificationPreferenceDto pref;
  final bool busy;
  final bool showDivider;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final label = labelFor(pref);
    return ListRow(
      title: label.title,
      subtitle: label.subtitle.isEmpty ? null : label.subtitle,
      showDivider: showDivider,
      onTap: busy ? null : onToggle,
      meta: AppToggle(value: pref.enabled, onChanged: busy ? null : (_) => onToggle()),
    );
  }
}
