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
            return const Center(child: Text('Cliente non trovato'));
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
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Column(
                  children: [
                    _infoRow(context, 'Ragione sociale', customer.companyName),
                    if (customer.taxId != null && customer.taxId!.isNotEmpty)
                      _infoRow(context, 'P.IVA', customer.taxId!),
                    if (customer.contactPerson != null && customer.contactPerson!.isNotEmpty)
                      _infoRow(context, 'Referente', customer.contactPerson!),
                    if (customer.phone != null && customer.phone!.isNotEmpty)
                      _infoRow(context, 'Telefono', customer.phone!),
                    if (customer.email != null && customer.email!.isNotEmpty)
                      _infoRow(context, 'Email', customer.email!),
                    if (customer.address != null && customer.address!.isNotEmpty)
                      _infoRow(context, 'Indirizzo', customer.address!),
                    if (customer.city != null && customer.city!.isNotEmpty)
                      _infoRow(context, 'Città', customer.city!),
                    if (customer.postalCode != null && customer.postalCode!.isNotEmpty)
                      _infoRow(context, 'CAP', customer.postalCode!),
                    if (customer.country != null && customer.country!.isNotEmpty)
                      _infoRow(context, 'Paese', customer.country!),
                  ],
                ),
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
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Note', style: AppTextStyles.titleMedium),
                      const SizedBox(height: 8),
                      Text(customer.notes!, style: AppTextStyles.bodyMedium),
                    ],
                  ),
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
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
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
        ),
        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
      ],
    );
  }

  static Widget _infoRow(BuildContext ctx, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: AppTextStyles.bodySmall.copyWith(color: ctx.colors.inkMuted)),
          ),
          Expanded(child: Text(value, style: AppTextStyles.bodyMedium)),
        ],
      ),
    );
  }
}
