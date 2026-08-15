// dart format width=100
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// All cantieri from Drift cache, alphabetical.
///
/// Reads the local mirror the sync now fills.
final adminCantieriProvider = StreamProvider.autoDispose<List<CantieriData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.cantieri)..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();
});

/// Admin cantiere list — with FAB to create.
class AdminCantiereListScreen extends StatefulWidget {
  const AdminCantiereListScreen({super.key});

  @override
  State<AdminCantiereListScreen> createState() => _AdminCantiereListScreenState();
}

class _AdminCantiereListScreenState extends State<AdminCantiereListScreen> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: _AdminCantiereListBody(
          query: _query,
          searchCtrl: _searchCtrl,
          onQueryChanged: (q) => setState(() => _query = q),
        ),
      ),
      floatingActionButton: AppFab(
        tooltip: 'Nuovo cantiere',
        onPressed: () => context.push('/altro/cantieri/nuovo'),
      ),
    );
  }
}

class _AdminCantiereListBody extends ConsumerWidget {
  const _AdminCantiereListBody({
    required this.query,
    required this.searchCtrl,
    required this.onQueryChanged,
  });

  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantieriAsync = ref.watch(adminCantieriProvider);
    final allCantieri = cantieriAsync.valueOrNull ?? [];

    final filtered = allCantieri.where((c) {
      if (query.isEmpty) return true;
      return c.name.toLowerCase().contains(query.toLowerCase()) ||
          (c.city?.toLowerCase().contains(query.toLowerCase()) ?? false);
    }).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(syncProvider.notifier).performSync(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'Cantieri',
              subtitle: '${filtered.length} totali',
              showBack: true,
            ),
          ),
          SliverToBoxAdapter(
            child: AppSearchBar(
              controller: searchCtrl,
              hint: 'Cerca per nome o città…',
              onChanged: onQueryChanged,
            ),
          ),
          if (cantieriAsync.isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()),
              ),
            )
          else if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: UnavailableState(
                icon: LucideIcons.hardHat,
                titolo: 'Cantieri non disponibili',
                motivo:
                    "L'elenco cantieri non è ancora sincronizzato sul "
                    'dispositivo. I cantieri creati con il pulsante + vengono '
                    'salvati sul server ma non compariranno in questa lista '
                    'finché la sincronizzazione non sarà collegata.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final cantiere = filtered[i];
                final cityLabel = cantiere.city ?? '—';
                return _AdminCantiereRow(
                  cantiere: cantiere,
                  cityLabel: cityLabel,
                  isLast: i == filtered.length - 1,
                );
              }, childCount: filtered.length),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}

class _AdminCantiereRow extends StatelessWidget {
  const _AdminCantiereRow({required this.cantiere, required this.cityLabel, required this.isLast});

  final CantieriData cantiere;
  final String cityLabel;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: context.colors.bg3,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(LucideIcons.hardHat, size: 20, color: context.colors.inkMuted),
      ),
      title: cantiere.name,
      subtitle: cityLabel,
      meta: Icon(LucideIcons.chevronRight, size: 16, color: context.colors.inkMuted),
      showDivider: !isLast,
      onTap: () => context.push('/altro/cantieri/${cantiere.id}'),
    );
  }
}
