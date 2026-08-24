// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/clienti/cliente_overview_api_client.dart';
import '../../../data/sync/sync_service.dart';
import '../../clienti/clienti_providers.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin customer detail — shows all fields + edit FAB.
class AdminCustomerDetailScreen extends ConsumerWidget {
  const AdminCustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailProvider(customerId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/clienti/$customerId/modifica');
          },
        ),
      ),
      body: customerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorState(onRetry: () => ref.invalidate(customerDetailProvider(customerId))),
        data: (customer) {
          if (customer == null) {
            return const UnavailableState(
              icon: LucideIcons.users,
              titolo: 'Cliente non disponibile',
              motivo:
                  "L'elenco clienti non è ancora sincronizzato sul "
                  'dispositivo, quindi questo cliente non può essere '
                  'letto dalla cache locale anche se esiste sul server.',
            );
          }
          return _CustomerDetailBody(customer: customer, customerId: customerId);
        },
      ),
    );
  }
}

/// Delete confirmation dialog + API call, shared by the header trash action.
///
/// Mirrors the confirm-then-call pattern already used for destructive actions elsewhere in the
/// app (e.g. `_removeMember` in admin_squadra_detail_screen.dart): a plain `AlertDialog` via
/// `showDialog<bool>`, no shared dialog widget exists yet in this codebase to reuse.
Future<void> _deleteCustomer(BuildContext context, WidgetRef ref, String customerId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminare il cliente?'),
      content: const Text(
        'Il cliente verrà disattivato. Sedi, contratti e interventi collegati '
        'restano consultabili ma non sarà più selezionabile per nuovi lavori.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(adminApiClientProvider).deleteCustomer(customerId);
    unawaited(ref.read(syncProvider.notifier).performSync());
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cliente eliminato')));
      context.pop(true);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Impossibile eliminare. Riprova.'),
          backgroundColor: context.colors.red,
        ),
      );
    }
  }
}

class _CustomerDetailBody extends ConsumerWidget {
  const _CustomerDetailBody({required this.customer, required this.customerId});
  final dynamic customer;
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: 'Cliente',
            subtitle: customer.companyName,
            showBack: true,
            actions: [
              HeaderIconBtn(
                icon: LucideIcons.trash2,
                label: 'Elimina cliente',
                glass: true,
                onTap: () => _deleteCustomer(context, ref, customerId),
              ),
            ],
          ),
        ),
        // ── Avatar hero ──────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: AppAvatar(name: customer.companyName, size: 64),
            ),
          ),
        ),
        // ── Anagrafica card ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Column(
                children: [
                  KeyVal(label: 'Ragione sociale', value: customer.companyName),
                  if (customer.taxId != null && customer.taxId!.isNotEmpty)
                    KeyVal(label: 'P.IVA', value: customer.taxId!),
                  if (customer.contactPerson != null && customer.contactPerson!.isNotEmpty)
                    KeyVal(label: 'Referente', value: customer.contactPerson!),
                  if (customer.phone != null && customer.phone!.isNotEmpty)
                    KeyVal(label: 'Telefono', value: customer.phone!),
                  if (customer.email != null && customer.email!.isNotEmpty)
                    KeyVal(label: 'Email', value: customer.email!),
                  if (customer.address != null && customer.address!.isNotEmpty)
                    KeyVal(label: 'Indirizzo', value: customer.address!),
                  if (customer.city != null && customer.city!.isNotEmpty)
                    KeyVal(label: 'Città', value: customer.city!),
                  if (customer.postalCode != null && customer.postalCode!.isNotEmpty)
                    KeyVal(label: 'CAP', value: customer.postalCode!),
                  KeyVal(
                    label: 'Paese',
                    value: customer.country != null && customer.country!.isNotEmpty
                        ? customer.country!
                        : '—',
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── Panoramica (sedi/contratti/interventi) ────────────────────────
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
            child: _OverviewCard(customerId: customerId),
          ),
        ),
        // ── Note ─────────────────────────────────────────────────────────
        if (customer.notes != null && customer.notes!.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(title: 'Note'),
                    const SizedBox(height: 4),
                    Text(customer.notes!, style: AppTextStyles.bodyMedium),
                  ],
                ),
              ),
            ),
          ),
        ],
        // ── Status ───────────────────────────────────────────────────────
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
            child: AppCard(
              child: Row(
                children: [
                  Text(
                    'Stato',
                    style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkMuted),
                  ),
                  const Spacer(),
                  StatusPill(stato: customer.isActive ? 'Attivo' : 'Inattivo', outlined: true),
                ],
              ),
            ),
          ),
        ),
        // ── Storico interventi ─────────────────────────────────────────────
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
            child: _TicketHistoryCard(customerId: customerId),
          ),
        ),
        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
      ],
    );
  }
}

/// The aggregated overview (sedi/contratti/interventi counts) from
/// `GET /api/app/clienti/{id}/overview` — data the API client + provider already fetched, just
/// never rendered anywhere (see `clienteOverviewProvider` in clienti_providers.dart).
class _OverviewCard extends ConsumerWidget {
  const _OverviewCard({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(clienteOverviewProvider(customerId));

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: overviewAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Text(
          e is ClienteOverviewOfflineException
              ? 'Panoramica non disponibile offline'
              : 'Panoramica non disponibile',
          style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
        ),
        data: (overview) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(title: 'Panoramica'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _OverviewStat(label: 'Sedi attive', value: '${overview.sediAttive}'),
                ),
                Expanded(
                  child: _OverviewStat(label: 'Contratti', value: '${overview.contratti}'),
                ),
                Expanded(
                  child: _OverviewStat(
                    label: 'Interventi',
                    value: '${overview.interventiTotali}',
                  ),
                ),
                Expanded(
                  child: _OverviewStat(label: 'Aperti', value: '${overview.interventiAperti}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.colors.inkMuted),
        ),
      ],
    );
  }
}

/// The customer's ticket history from the local Drift cache — `ticketsForCustomerProvider`
/// existed with no widget consuming it.
class _TicketHistoryCard extends ConsumerWidget {
  const _TicketHistoryCard({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(ticketsForCustomerProvider(customerId));

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: ticketsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Text(
          'Storico interventi non disponibile',
          style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
        ),
        data: (tickets) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(title: 'Storico interventi', trailing: '${tickets.length}'),
            const SizedBox(height: 4),
            if (tickets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nessun intervento registrato per questo cliente.',
                  style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
                ),
              )
            else
              for (var i = 0; i < tickets.length; i++)
                ListRow(
                  title: tickets[i].title,
                  subtitle: tickets[i].numero != null ? '#${tickets[i].numero}' : '—',
                  showDivider: i < tickets.length - 1,
                  onTap: () => context.push('/ticket/${tickets[i].id}'),
                ),
          ],
        ),
      ),
    );
  }
}
