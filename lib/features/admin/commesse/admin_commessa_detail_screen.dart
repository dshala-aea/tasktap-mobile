// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_rack.dart';
import '../../../core/widgets/vetro_card.dart';
import '../../../core/widgets/widgets.dart';
import '../../ticket/ticket_providers.dart';
import 'commesse_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Commessa detail — a genuinely missing screen, not a re-skin. Every other module in the Vetro
/// mockup already had at least a read-only detail screen on mobile; Commessa only ever surfaced
/// as a resolved codice on Ticket/Cantiere detail (module #13 of the feature audit), with no
/// screen of its own to land on. Read-only throughout, same scope the audit gave every other
/// deferred-CRUD entity here (Contratto, Asset): fields from `Commessa.cs` (Codice, Stato,
/// DataApertura/DataChiusura, Importo, Note), no create/edit/delete. The audit itself deferred any
/// cost-vs-Importo rollup — no hourly-rate concept exists in the system yet — so this only ever
/// displays what the entity already states.
class AdminCommessaDetailScreen extends ConsumerWidget {
  const AdminCommessaDetailScreen({super.key, required this.commessaId});

  final String commessaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commessaAsync = ref.watch(commessaByIdProvider(commessaId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: commessaAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Column(
            children: [
              ScreenHeader(title: 'Commessa', showBack: true),
              Expanded(
                child: ErrorState(
                  onRetry: () => ref.invalidate(commessaByIdProvider(commessaId)),
                ),
              ),
            ],
          ),
          data: (commessa) {
            if (commessa == null) {
              return Column(
                children: [
                  ScreenHeader(title: 'Commessa', showBack: true),
                  const Expanded(
                    child: UnavailableState(
                      titolo: 'Commessa non disponibile',
                      motivo: 'La commessa richiesta non è stata trovata sul server.',
                    ),
                  ),
                ],
              );
            }
            return _CommessaDetailBody(commessa: commessa, commessaId: commessaId);
          },
        ),
      ),
    );
  }
}

class _CommessaDetailBody extends ConsumerWidget {
  const _CommessaDetailBody({required this.commessa, required this.commessaId});

  final Map<String, dynamic> commessa;
  final String commessaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codice = commessa['codice'] as String? ?? '—';
    final descrizione = commessa['descrizione'] as String?;
    final stato = commessa['stato'] as String? ?? 'Aperta';
    final note = commessa['note'] as String?;
    final importo = commessa['importo'];
    final importoLabel = importo is num ? '€ ${importo.toStringAsFixed(2)}' : '—';

    String dateLabel(String? key) {
      final raw = commessa[key] as String?;
      return raw != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(raw)) : '—';
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: descrizione != null && descrizione.isNotEmpty ? descrizione : codice,
            subtitle: 'Commessa $codice',
            showBack: true,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.pagePadding,
              AppSpacing.pagePadding,
              0,
            ),
            child: StatusPill(stato: stato, outlined: true),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
            child: VetroCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(title: 'Dettagli'),
                  const SizedBox(height: 4),
                  KeyVal(label: 'Data apertura', value: dateLabel('dataApertura')),
                  KeyVal(label: 'Data chiusura', value: dateLabel('dataChiusura')),
                  KeyVal(
                    label: 'Importo',
                    value: importoLabel,
                    showDivider: note != null && note.isNotEmpty,
                  ),
                  if (note != null && note.isNotEmpty)
                    KeyVal(label: 'Note', value: note, showDivider: false),
                ],
              ),
            ),
          ),
        ),

        // ── Cantieri collegati ──────────────────────────────────────────
        Consumer(
          builder: (context, ref, _) {
            final cantieriAsync = ref.watch(cantieriForCommessaProvider(commessaId));
            final cantieri = cantieriAsync.valueOrNull ?? const [];
            if (cantieri.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
            return SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  SectionTitle(title: 'Cantieri collegati', trailing: '${cantieri.length}'),
                  for (var i = 0; i < cantieri.length; i++)
                    ListRow(
                      leading: const RowIconTile(icon: LucideIcons.hardHat),
                      title: cantieri[i].name,
                      subtitle: cantieri[i].city,
                      onTap: () => context.push('/altro/cantieri/${cantieri[i].id}'),
                      showDivider: i < cantieri.length - 1,
                    ),
                ],
              ),
            );
          },
        ),

        // ── Ticket collegati ─────────────────────────────────────────────
        Consumer(
          builder: (context, ref, _) {
            final ticketsAsync = ref.watch(ticketsForCommessaProvider(commessaId));
            final statusMap = ref.watch(ticketStatusMapProvider).valueOrNull ?? {};
            final tickets = ticketsAsync.valueOrNull ?? const [];
            if (tickets.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
            return SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  SectionTitle(title: 'Ticket collegati', trailing: '${tickets.length}'),
                  for (var i = 0; i < tickets.length; i++)
                    ListRow(
                      leading: const RowIconTile(icon: LucideIcons.clipboardList),
                      title: tickets[i].numero != null
                          ? '${tickets[i].numero} · ${tickets[i].title}'
                          : tickets[i].title,
                      meta: StatusPill(
                        stato: statusMap[tickets[i].statusId] ?? 'Aperto',
                        small: true,
                        outlined: true,
                      ),
                      onTap: () => context.push('/ticket/${tickets[i].id}'),
                      showDivider: i < tickets.length - 1,
                    ),
                ],
              ),
            );
          },
        ),

        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
      ],
    );
  }
}
