// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/widgets.dart';
import '../../clienti/clienti_providers.dart';
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
          return _CustomerDetailBody(customer: customer);
        },
      ),
    );
  }
}

class _CustomerDetailBody extends StatelessWidget {
  const _CustomerDetailBody({required this.customer});
  final dynamic customer;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(title: 'Cliente', subtitle: customer.companyName, showBack: true),
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
                  StatusPill(stato: customer.isActive ? 'Attivo' : 'Inattivo'),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
      ],
    );
  }
}
