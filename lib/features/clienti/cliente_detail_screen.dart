import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import 'clienti_providers.dart';

class ClienteDetailScreen extends ConsumerWidget {
  const ClienteDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailProvider(customerId));

    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: customerAsync.when(
        loading: () => const SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => SafeArea(
          child: Center(child: Text('Errore: $e')),
        ),
        data: (customer) {
          if (customer == null) {
            return SafeArea(
              child: Column(
                children: [
                  ScreenHeader(
                    title: 'Cliente',
                    showBack: true,
                  ),
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
    final ticketsAsync =
        ref.watch(ticketsForCustomerProvider(customer.id));
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
              padding: const EdgeInsets.fromLTRB(19, 0, 19, 20),
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
                          style: GoogleFonts.sora(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.DARK,
                          ),
                        ),
                        if (customer.city != null && customer.city!.isNotEmpty)
                          Text(
                            customer.city!,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: AppColors.MUTED,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Anagrafica KeyVal card
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(19, 0, 19, 16),
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                padding: const EdgeInsets.fromLTRB(19, 0, 19, 16),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(title: 'Note'),
                      const SizedBox(height: 4),
                      Text(
                        customer.notes!,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          color: AppColors.DARK,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Ticket section title
          const SliverToBoxAdapter(
            child: SectionTitle(title: 'Ticket'),
          ),

          // Ticket list
          if (ticketsAsync.isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (tickets.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(19, 0, 19, 0),
                child: EmptyState(
                  icon: LucideIcons.ticket,
                  title: 'Nessun ticket',
                  body: 'Nessun ticket collegato a questo cliente.',
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final ticket = tickets[i];
                  final shortId = ticket.id.length > 8
                      ? ticket.id.substring(0, 8)
                      : ticket.id;
                  final dateLabel = DateFormat('dd/MM/yy', 'it')
                      .format(ticket.createdAt.toLocal());
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 19),
                    child: AppCard(
                      padding: EdgeInsets.zero,
                      child: ListRow(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.BG3,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            LucideIcons.ticket,
                            size: 20,
                            color: AppColors.MUTED,
                          ),
                        ),
                        title: ticket.title,
                        subtitle: '#$shortId',
                        meta: Text(
                          dateLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.MUTED,
                          ),
                        ),
                        showDivider: false,
                        onTap: () => context.push('/ticket/${ticket.id}'),
                      ),
                    ),
                  );
                },
                childCount: tickets.length,
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}
