// dart format width=100
// lib/features/cantiere/cantiere_detail_screen.dart
//
// Cantiere info + the "Timbra cantiere" action (relocated from ticket detail — see this app's
// nav-restructure spec) + tickets linked to this cantiere. Reached from CantieriListScreen (no
// ticketId) or from a ticket's cantiere chip (ticketId set, carried through to the Timbra action
// so the resulting session still gets tagged the way it did when the button lived on the ticket).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import 'cantiere_providers.dart';

class CantiereDetailScreen extends ConsumerWidget {
  const CantiereDetailScreen({super.key, required this.cantiereId, this.ticketId});

  final String cantiereId;

  /// Carried through from a ticket's cantiere chip, when reached that way — see this file's own
  /// header comment. Null when reached from the Cantieri tab directly.
  final String? ticketId;

  static String _statusLabel(int status) {
    switch (status) {
      case 0:
        return 'Attivo';
      case 1:
        return 'Completato';
      case 2:
        return 'Annullato';
      default:
        return '—';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantiereAsync = ref.watch(cantiereByIdProvider(cantiereId));
    final ticketsAsync = ref.watch(ticketsForCantiereProvider(cantiereId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenHeader(title: 'Cantiere', showBack: true),
            Expanded(
              child: cantiereAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const UnavailableState(
                  icon: LucideIcons.hardHat,
                  titolo: 'Impossibile caricare il cantiere',
                  motivo: 'Riprova tra poco.',
                ),
                data: (cantiere) {
                  if (cantiere == null) {
                    return const UnavailableState(
                      icon: LucideIcons.hardHat,
                      titolo: 'Cantiere non trovato',
                      motivo: 'Non risulta sincronizzato su questo dispositivo.',
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pagePadding,
                      AppSpacing.sm,
                      AppSpacing.pagePadding,
                      AppSpacing.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cantiere.name,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.ink,
                                ),
                              ),
                              if (cantiere.address != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  cantiere.address!,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    color: context.colors.inkMuted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              AppBadge(label: _statusLabel(cantiere.status)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        AppButton(
                          label: 'Timbra cantiere',
                          icon: const Icon(LucideIcons.mapPin),
                          onPressed: () => context.push(
                            AppRoutes.cantiereTimbraPath(
                              cantiereId: cantiere.id,
                              ticketId: ticketId,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const SectionTitle(title: 'Ticket collegati'),
                        const SizedBox(height: 8),
                        ticketsAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Text(
                            'Impossibile caricare i ticket collegati.',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: context.colors.red,
                            ),
                          ),
                          data: (tickets) {
                            if (tickets.isEmpty) {
                              return Text(
                                'Nessun ticket collegato',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  color: context.colors.inkMuted,
                                ),
                              );
                            }
                            return AppCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: tickets.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final t = entry.value;
                                  return ListRow(
                                    title: t.title,
                                    showDivider: i != tickets.length - 1,
                                    onTap: () =>
                                        context.push(AppRoutes.ticketDetailPath(t.id)),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
