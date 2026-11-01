import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/widgets.dart';
import 'notifica_ui.dart';
import 'notifiche_provider.dart';

/// One notification, read in full.
///
/// Opened by the taps that have nothing else to open (an announcement, a notice):
/// the list clips the body and had nowhere to send the reader. The page loads by
/// id alone, so a push tap works without the list, and it never reads list state.
class NotificaDetailScreen extends ConsumerStatefulWidget {
  const NotificaDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<NotificaDetailScreen> createState() =>
      _NotificaDetailScreenState();
}

class _NotificaDetailScreenState extends ConsumerState<NotificaDetailScreen> {
  bool _markedRead = false;

  @override
  Widget build(BuildContext context) {
    final provider = notificaDettaglioProvider(widget.id);

    // Best effort: reading the text must never wait on, or fail because of, the
    // read receipt. The notifier also updates the local mirror and the badge.
    ref.listen(provider, (_, next) {
      next.whenData((n) {
        if (!n.letta && !_markedRead) {
          _markedRead = true;
          // Swallowed on purpose: the page is already readable, and a failed
          // receipt (offline, revoked token) must not become an unhandled error.
          unawaited(
            ref
                .read(notificheProvider.notifier)
                .segnaLetta(n.id)
                .catchError((_) {}),
          );
        }
      });
    });

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Notifica', showBack: true),
            Expanded(
              child: ref
                  .watch(provider)
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => e is NotificaNonDisponibile
                        ? const UnavailableState(
                            icon: LucideIcons.bellOff,
                            titolo: 'Notifica non disponibile',
                            motivo:
                                'Potrebbe essere stata eliminata o non appartenere al tuo account.',
                          )
                        : ErrorState(
                            onRetry: () => ref.invalidate(provider),
                          ),
                    data: (n) => _NotificaBody(notifica: n),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificaBody extends StatelessWidget {
  const _NotificaBody({required this.notifica});

  final AppNotifica notifica;

  @override
  Widget build(BuildContext context) {
    final etichetta = notificaEtichettaTipo(notifica.tipo);
    final quando = DateFormat(
      'd MMMM yyyy, HH:mm',
      'it',
    ).format(notifica.timestamp.toLocal());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(notifica.titolo, style: AppTextStyles.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Icon(
                notificaIcon(notifica.tipo),
                size: 16,
                color: context.colors.inkMuted,
              ),
              if (etichetta != null)
                Text(
                  etichetta,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: context.colors.inkMuted,
                  ),
                ),
              Text(
                quando,
                style: AppTextStyles.bodySmall.copyWith(
                  color: context.colors.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // No maxLines and no ellipsis: the whole point of this page.
          Text(notifica.corpo, style: AppTextStyles.bodyLarge),
        ],
      ),
    );
  }
}
