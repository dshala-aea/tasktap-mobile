// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../admin_api_client.dart';

/// Fetches prodotti assistenza from backend API.
final adminProdottiAssistenzaProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(adminApiClientProvider);
  return api.fetchProdottiAssistenza();
});

/// Admin prodotto assistenza list — online-only.
class AdminProdottoListScreen extends ConsumerWidget {
  const AdminProdottoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prodottiAsync = ref.watch(adminProdottiAssistenzaProvider);

    return Scaffold(
      backgroundColor: AppColors.BG2,
      body: SafeArea(
        child: prodottiAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Errore: $e')),
          data: (prodotti) => _ProdottoListBody(prodotti: prodotti),
        ),
      ),
      floatingActionButton: AppFab(
        tooltip: 'Nuovo prodotto',
        onPressed: () => context.push('/altro/prodotti/nuovo'),
      ),
    );
  }
}

class _ProdottoListBody extends ConsumerStatefulWidget {
  const _ProdottoListBody({required this.prodotti});

  final List<Map<String, dynamic>> prodotti;

  @override
  ConsumerState<_ProdottoListBody> createState() => _ProdottoListBodyState();
}

class _ProdottoListBodyState extends ConsumerState<_ProdottoListBody> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.prodotti.where((p) {
      if (_query.isEmpty) return true;
      final name = (p['name'] as String? ?? '').toLowerCase();
      return name.contains(_query.toLowerCase());
    }).toList();

    final customersAsync = ref.watch(allCustomersProvider);
    final customers = customersAsync.valueOrNull ?? [];
    final customerMap = {for (final c in customers) c.id: c.companyName};

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: 'Prodotti Assistenza',
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
              icon: LucideIcons.wrench,
              title: 'Nessun prodotto',
              body: 'Crea un nuovo prodotto con il pulsante +.',
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final prodotto = filtered[i];
                final name = prodotto['name'] as String? ?? '';
                final customerId = prodotto['customerId'] as String? ?? '';
                final customerName = customerMap[customerId] ?? '—';
                final isActive = prodotto['isActive'] as bool? ?? true;
                return _ProdottoRow(
                  name: name,
                  customerName: customerName,
                  isActive: isActive,
                  isLast: i == filtered.length - 1,
                  onTap: () => context.push(
                    '/altro/prodotti/${prodotto['id']}',
                    extra: prodotto,
                  ),
                );
              },
              childCount: filtered.length,
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }
}

class _ProdottoRow extends StatelessWidget {
  const _ProdottoRow({
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
          LucideIcons.wrench,
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
