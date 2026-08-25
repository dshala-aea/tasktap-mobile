// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Fetches squadre from backend API.
final adminSquadreProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.watch(adminApiClientProvider);
  return api.fetchSquadre();
});

/// Backs per-squadra member counts here (Gap 7 of the feature audit) and, on the detail screen,
/// each member's last-access display (Gap 6) — one shared bulk fetch rather than either fetching
/// per squadra row or per member row. See
/// [AdminApiClient.fetchAllUsersWithSquadraInfo]'s doc comment for why.
final allUsersWithSquadraProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
  final api = ref.watch(adminApiClientProvider);
  return api.fetchAllUsersWithSquadraInfo();
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
          error: (e, _) => ErrorState(onRetry: () => ref.invalidate(adminSquadreProvider)),
          data: (squadre) => _SquadraListBody(squadre: squadre),
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          tooltip: 'Nuova squadra',
          onPressed: () => context.push('/altro/squadre/nuovo'),
        ),
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

    // One bulk fetch for the whole list, not one per row — see allUsersWithSquadraProvider's doc
    // comment. `squadraId` is the derived field UsersController.PopulateSquadreAsync projects onto
    // every user response.
    final users = ref.watch(allUsersWithSquadraProvider).valueOrNull ?? const [];
    final memberCounts = <String, int>{};
    for (final u in users) {
      final squadraId = u['squadraId'] as String?;
      if (squadraId != null) {
        memberCounts[squadraId] = (memberCounts[squadraId] ?? 0) + 1;
      }
    }

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
              delegate: SliverChildBuilderDelegate((context, i) {
                final squadra = filtered[i];
                final nome = squadra['nome'] as String? ?? '';
                final spec = squadra['specializzazione'] as String? ?? '';
                final colore = squadra['coloreCalendario'] as String?;
                // Backend derives this on every /api/squadre response (PopulateCapiSquadraAsync
                // in SquadreController) — it was never read on mobile.
                final capoNome = squadra['capSquadraNome'] as String?;
                final memberCount = memberCounts[squadra['id'] as String? ?? ''] ?? 0;
                return _SquadraRow(
                  nome: nome,
                  specializzazione: spec,
                  capoNome: capoNome,
                  memberCount: memberCount,
                  colore: colore,
                  isLast: i == filtered.length - 1,
                  onTap: () => context.push('/altro/squadre/${squadra['id']}', extra: squadra),
                );
              }, childCount: filtered.length),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }
}

class _SquadraRow extends StatelessWidget {
  const _SquadraRow({
    required this.nome,
    required this.specializzazione,
    this.capoNome,
    required this.memberCount,
    required this.colore,
    required this.isLast,
    required this.onTap,
  });

  final String nome;
  final String specializzazione;
  final String? capoNome;

  /// Derived client-side from `allUsersWithSquadraProvider` — the backend has no `membriCount`
  /// field on the squadra list response (Gap 7 of the feature audit; web's own `nMembri` column
  /// renders 0 for the same reason, per its `api.ts` header comment).
  final int memberCount;
  final String? colore;
  final bool isLast;
  final VoidCallback onTap;

  String get _membriLabel => memberCount == 1 ? '1 membro' : '$memberCount membri';

  String get _subtitle {
    final hasCapo = capoNome != null && capoNome!.isNotEmpty;
    if (specializzazione.isNotEmpty && hasCapo) {
      return '$specializzazione · Capo: $capoNome · $_membriLabel';
    }
    if (hasCapo) return 'Capo: $capoNome · $_membriLabel';
    if (specializzazione.isNotEmpty) return '$specializzazione · $_membriLabel';
    return _membriLabel;
  }

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
          borderRadius: AppRack.insetShape,
        ),
        child: Icon(LucideIcons.users, size: 20, color: _parseColor(context, colore)),
      ),
      title: nome,
      subtitle: _subtitle,
      showDivider: !isLast,
      onTap: onTap,
    );
  }
}
