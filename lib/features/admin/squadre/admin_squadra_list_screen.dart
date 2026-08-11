// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Fetches squadre from backend API.
final adminSquadreProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(adminApiClientProvider);
  return api.fetchSquadre();
});

/// Admin squadra list — online-only.
class AdminSquadraListScreen extends ConsumerWidget {
  const AdminSquadraListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final squadreAsync = ref.watch(adminSquadreProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: squadreAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Errore: $e')),
          data: (squadre) => _SquadraListBody(squadre: squadre),
        ),
      ),
      floatingActionButton: AppFab(
        tooltip: 'Nuova squadra',
        onPressed: () => context.push('/altro/squadre/nuovo'),
      ),
    );
  }
}

class _SquadraListBody extends ConsumerStatefulWidget {
  const _SquadraListBody({required this.squadre});

  final List<Map<String, dynamic>> squadre;

  @override
  ConsumerState<_SquadraListBody> createState() => _SquadraListBodyState();
}

class _SquadraListBodyState extends ConsumerState<_SquadraListBody> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.squadre.where((s) {
      if (_query.isEmpty) return true;
      final nome = (s['nome'] as String? ?? '').toLowerCase();
      return nome.contains(_query.toLowerCase());
    }).toList();

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminSquadreProvider.future),
      child: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: 'Squadre',
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
              icon: LucideIcons.users,
              title: 'Nessuna squadra',
              body: 'Crea una nuova squadra con il pulsante +.',
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final squadra = filtered[i];
                final nome = squadra['nome'] as String? ?? '';
                final spec = squadra['specializzazione'] as String? ?? '';
                final colore = squadra['coloreCalendario'] as String?;
                return _SquadraRow(
                  nome: nome,
                  specializzazione: spec,
                  colore: colore,
                  isLast: i == filtered.length - 1,
                  onTap: () => context.push(
                    '/altro/squadre/${squadra['id']}',
                    extra: squadra,
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

class _SquadraRow extends StatelessWidget {
  const _SquadraRow({
    required this.nome,
    required this.specializzazione,
    required this.colore,
    required this.isLast,
    required this.onTap,
  });

  final String nome;
  final String specializzazione;
  final String? colore;
  final bool isLast;
  final VoidCallback onTap;

  Color _parseColor(BuildContext context, String? hex) {
    if (hex == null || hex.isEmpty) return context.colors.inkMuted;
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return context.colors.inkMuted;
    return Color(int.parse('FF$clean', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return ListRow(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _parseColor(context, colore).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          LucideIcons.users,
          size: 20,
          color: _parseColor(context, colore),
        ),
      ),
      title: nome,
      subtitle: specializzazione.isNotEmpty ? specializzazione : '—',
      meta: Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: context.colors.inkMuted,
      ),
      showDivider: !isLast,
      onTap: onTap,
    );
  }
}
