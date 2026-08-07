// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../admin_api_client.dart';

/// Fetches contracts from backend API.
final adminContractsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(adminApiClientProvider);
  return api.fetchContracts();
});

/// Admin contract list — online-only.
class AdminContractListScreen extends ConsumerWidget {
  const AdminContractListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(adminContractsProvider);

    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: contractsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Errore: $e')),
          data: (contracts) => _ContractListBody(contracts: contracts),
        ),
      ),
      floatingActionButton: AppFab(
        tooltip: 'Nuovo contratto',
        onPressed: () => context.push('/altro/contratti/nuovo'),
      ),
    );
  }
}

class _ContractListBody extends ConsumerStatefulWidget {
  const _ContractListBody({required this.contracts});

  final List<Map<String, dynamic>> contracts;

  @override
  ConsumerState<_ContractListBody> createState() => _ContractListBodyState();
}

class _ContractListBodyState extends ConsumerState<_ContractListBody> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.contracts.where((c) {
      if (_query.isEmpty) return true;
      final name = (c['name'] as String? ?? '').toLowerCase();
      return name.contains(_query.toLowerCase());
    }).toList();

    final customersAsync = ref.watch(allCustomersProvider);
    final customers = customersAsync.valueOrNull ?? [];
    final customerMap = {for (final c in customers) c.id: c.companyName};

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminContractsProvider.future),
      child: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: 'Contratti',
            subtitle: '${filtered.length} totali',
            showBack: true,
          ),
        ),
        SliverToBoxAdapter(
          child: AppSearchBar(
            controller: _searchCtrl,
            hint: 'Cerca per nome…',
            onChanged: (q) => setState(() => _query = q),
          ),
        ),
        if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              icon: LucideIcons.fileSignature,
              title: 'Nessun contratto',
              body: 'Crea un nuovo contratto con il pulsante +.',
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final contract = filtered[i];
                final name = contract['name'] as String? ?? '';
                final customerId = contract['customerId'] as String? ?? '';
                final customerName = customerMap[customerId] ?? '—';
                final isActive = contract['isActive'] as bool? ?? true;
                return _ContractRow(
                  name: name,
                  customerName: customerName,
                  isActive: isActive,
                  isLast: i == filtered.length - 1,
                  onTap: () => context.push(
                    '/altro/contratti/${contract['id']}',
                    extra: contract,
                  ),
                );
              },
              childCount: filtered.length,
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
      ),
    );
  }
}

class _ContractRow extends StatelessWidget {
  const _ContractRow({
    required this.name,
    required this.customerName,
    required this.isActive,
    required this.isLast,
    required this.onTap,
  });

  final String name;
  final String customerName;
  final bool isActive;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.BG3,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          LucideIcons.fileSignature,
          size: 20,
          color: AppColors.MUTED,
        ),
      ),
      title: name,
      subtitle: customerName,
      meta: const Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: AppColors.MUTED,
      ),
      showDivider: !isLast,
      onTap: onTap,
    );
  }
}
