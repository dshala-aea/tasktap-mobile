import 'package:flutter/material.dart';
import '../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/clienti/cliente_overview_api_client.dart';
import '../ticket/ticket_label.dart';
import 'clienti_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

class ClienteDetailScreen extends ConsumerWidget {
  const ClienteDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailProvider(customerId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: customerAsync.when(
        loading: () =>
            const SafeArea(child: Center(child: CircularProgressIndicator())),
        error: (e, _) => SafeArea(child: Center(child: Text('Errore: $e'))),
        data: (customer) {
          if (customer == null) {
            return SafeArea(
              child: Column(
                children: [
                  ScreenHeader(title: 'Cliente', showBack: true),
                  EmptyState(
                    icon: LucideIcons.xCircle,
                    title: 'Cliente non trovato',
                    body: 'Il cliente richiesto non è disponibile in cache.',
                  ),
                ],
              ),
            );
          }
          return _ClienteDetailBody(customer: customer);
        },
      ),
    );
  }
}

class _ClienteDetailBody extends ConsumerWidget {
  const _ClienteDetailBody({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(ticketsForCustomerProvider(customer.id));
    final tickets = ticketsAsync.valueOrNull ?? [];

    final addressParts = [
      customer.address,
      customer.city,
      customer.postalCode,
      customer.country,
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // Header with back + avatar
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: customer.companyName,
              subtitle: customer.city,
              showBack: true,
            ),
          ),

          // Avatar hero
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                0,
                AppSpacing.pagePadding,
                AppSpacing.lg,
              ),
              child: Row(
                children: [
                  AppAvatar(name: customer.companyName, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.companyName,
                          style: TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: context.colors.ink,
                          ),
                        ),
                        if (customer.city != null && customer.city!.isNotEmpty)
                          Text(
                            customer.city!,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 13,
                              color: context.colors.inkMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Counts and fiscal detail, from the server. Additive: everything below still renders
          // from the local mirror whether or not this resolves.
          SliverToBoxAdapter(
            child: _ClienteOverviewSection(customerId: customer.id),
          ),

          // Anagrafica KeyVal card
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                0,
                AppSpacing.pagePadding,
                AppSpacing.base,
              ),
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                ),
                child: Column(
                  children: [
                    KeyVal(
                      label: 'P.IVA',
                      value: customer.taxId?.isNotEmpty == true
                          ? customer.taxId!
                          : '—',
                    ),
                    KeyVal(
                      label: 'Indirizzo',
                      value: addressParts.isNotEmpty ? addressParts : '—',
                    ),
                    KeyVal(
                      label: 'Telefono',
                      value: customer.phone?.isNotEmpty == true
                          ? customer.phone!
                          : '—',
                    ),
                    KeyVal(
                      label: 'Email',
                      value: customer.email?.isNotEmpty == true
                          ? customer.email!
                          : '—',
                    ),
                    KeyVal(
                      label: 'Referente',
                      value: customer.contactPerson?.isNotEmpty == true
                          ? customer.contactPerson!
                          : '—',
                      showDivider: false,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Note card (only when present)
          if (customer.notes != null && customer.notes!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  0,
                  AppSpacing.pagePadding,
                  AppSpacing.base,
                ),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(title: 'Note'),
                      const SizedBox(height: 4),
                      Text(
                        customer.notes!,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 13,
                          color: context.colors.ink,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Ticket section title
          const SliverToBoxAdapter(child: SectionTitle(title: 'Ticket')),

          // Ticket list
          if (ticketsAsync.isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (tickets.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  0,
                  AppSpacing.pagePadding,
                  0,
                ),
                child: EmptyState(
                  icon: LucideIcons.ticket,
                  title: 'Nessun ticket',
                  body: 'Nessun ticket collegato a questo cliente.',
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final ticket = tickets[i];
                final reference = ticketReference(ticket.numero);
                final dateLabel = DateFormat(
                  'dd/MM/yy',
                  'it',
                ).format(ticket.createdAt.toLocal());
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pagePadding,
                  ),
                  child: ListRow(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: context.colors.bg3,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        LucideIcons.ticket,
                        size: 20,
                        color: context.colors.inkMuted,
                      ),
                    ),
                    title: ticket.title,
                    subtitle: reference,
                    meta: Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 10,
                        color: context.colors.inkMuted,
                      ),
                    ),
                    showDivider: false,
                    onTap: () => context.push('/ticket/${ticket.id}'),
                  ),
                );
              }, childCount: tickets.length),
            ),

          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Server-side overview
// ══════════════════════════════════════════════════════════════════════════════

/// The four counts and the fiscal fields the synced `customers` table has no columns for.
///
/// Strictly additive. The rest of this screen reads Drift and is unaffected by whatever happens
/// here, which is the whole reason this is a separate section rather than a rewrite of the
/// anagrafica card: a customer's address and phone must still be readable in a basement.
class _ClienteOverviewSection extends ConsumerWidget {
  const _ClienteOverviewSection({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final async = ref.watch(clienteOverviewProvider(customerId));

    return async.when(
      // No spinner. This section is an extra on a screen that is already fully rendered from the
      // mirror; a progress indicator here would suggest the page is incomplete when it is not.
      loading: () => const SizedBox.shrink(),

      error: (e, _) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pagePadding,
          0,
          AppSpacing.pagePadding,
          AppSpacing.base,
        ),
        child: Row(
          children: [
            Icon(
              e is ClienteOverviewOfflineException
                  ? LucideIcons.cloudOff
                  : LucideIcons.alertCircle,
              size: 14,
              color: c.inkMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                e is ClienteOverviewOfflineException
                    ? 'Dati fiscali e conteggi non disponibili offline.'
                    : 'Dati fiscali e conteggi non caricati.',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  color: c.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ),

      data: (o) {
        final fiscal = <(String, String?)>[
          ('Cod. fiscale', o.codiceFiscale),
          ('PEC', o.pec),
          ('Codice SDI', o.sdiCode),
          ('Provincia', o.provincia),
          ('Referente', o.contatto),
        ].where((r) => r.$2 != null && r.$2!.isNotEmpty).toList();

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            0,
            AppSpacing.pagePadding,
            AppSpacing.base,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: StatsGrid(
                  items: [
                    StatItem(label: 'Sedi attive', value: '${o.sediAttive}'),
                    StatItem(label: 'Contratti', value: '${o.contratti}'),
                    StatItem(
                      label: 'Interventi',
                      value: '${o.interventiTotali}',
                    ),
                    StatItem(label: 'Aperti', value: '${o.interventiAperti}'),
                  ],
                ),
              ),
              if (fiscal.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < fiscal.length; i++)
                        KeyVal(
                          label: fiscal[i].$1,
                          value: fiscal[i].$2!,
                          showDivider: i != fiscal.length - 1,
                        ),
                    ],
                  ),
                ),
              ],
              if (!o.attivo)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Icon(LucideIcons.alertTriangle, size: 14, color: c.red),
                      const SizedBox(width: 8),
                      // Worth stating: the mirror's own isActive can lag, and a technician about
                      // to book work against a deactivated customer should find out here.
                      Text(
                        'Cliente non attivo',
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.red,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
