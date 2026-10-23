// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/utils/error_message.dart' show isTransportOrServerFault;
import '../../../core/widgets/widgets.dart';
import '../../../data/reference/reference_cache_repository.dart';
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../../presentation/providers/schedule_providers.dart';
import '../../ticket/ticket_detail_api_client.dart' show TicketDetailOfflineException;
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// The Contratti list's rows, plus where they came from.
///
/// [fromMirror] is not diagnostic noise: a mirrored list is a *scoped* one, so the screen has to
/// say so (see [MirrorNotice]) instead of letting "12 totali" read as the whole book of business.
class ContractListRows {
  const ContractListRows(this.rows, {required this.fromMirror});

  final List<Map<String, dynamic>> rows;
  final bool fromMirror;
}

/// The tenant's contracts — from the server when it answers, from the synced mirror otherwise.
///
/// Online the server answers, because an office edit made a minute ago only exists there. When the
/// request never arrived (the radio says online but nothing came back) or the server itself
/// faulted, the mirror answers instead; offline it answers from the start. A 4xx is never
/// second-guessed — a 401/403 is about this account, not about connectivity, and hiding it behind
/// a list of stale rows would misreport why the page is empty.
///
/// The mirror carries fewer fields than `GET /api/contracts`: `tipo` is stored as the C# ordinal
/// but the wire shape is the enum's *name* (`"Manutenzione"`), and `price`, `condizioni`,
/// `frequency*`, `autoRenewal` and `scadenzaGiorni` are not synced at all. Those read as absent on
/// the detail screen instead of being converted from a guess — an ordinal mapped through an
/// assumed ordering is a wrong value that looks right.
final adminContractsProvider = FutureProvider.autoDispose<ContractListRows>((ref) async {
  Future<ContractListRows> fromMirror() async {
    final db = ref.watch(appDatabaseProvider);
    final rows = await ref.watch(referenceCacheProvider).allContracts();
    // An empty mirror means one of two very different things: nothing was ever downloaded (say
    // so, and point at a connection), or the sync ran and this account genuinely has no contracts
    // (an empty list, with the list's own "Nessun contratto" copy).
    if (rows.isEmpty && await db.getLastSync() == null) {
      throw const TicketDetailOfflineException();
    }
    return ContractListRows([
      for (final c in rows)
        {
          'id': c.id,
          'name': c.name,
          'customerId': c.customerId,
          'locationId': c.locationId,
          // Re-stamped to UTC for the same reason contractByIdProvider does it: Drift hands a
          // DateTimeColumn back as a LOCAL-kind instant, and the detail screen parses these
          // strings as the server's own `Z`-suffixed dates.
          'startDate': c.startDate.toUtc().toIso8601String(),
          'endDate': c.endDate?.toUtc().toIso8601String(),
          'isActive': c.isActive,
          'numero': c.numero,
          'codice': c.codice,
          'externalId': c.externalId,
        },
    ], fromMirror: true);
  }

  if (ref.watch(isOnlineProvider)) {
    try {
      final rows = await ref.watch(adminApiClientProvider).fetchContracts();
      return ContractListRows(rows, fromMirror: false);
    } catch (e) {
      if (!isTransportOrServerFault(e)) rethrow;
    }
  }
  return fromMirror();
});

/// Admin contract list — server-first, mirror when it cannot be reached.
class AdminContractListScreen extends ConsumerWidget {
  const AdminContractListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(adminContractsProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: contractsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => e is TicketDetailOfflineException
              ? const UnavailableState(
                  icon: LucideIcons.fileSignature,
                  titolo: 'Contratti non disponibili offline',
                  motivo:
                      'Questo dispositivo non ha ancora scaricato i contratti. Apri questa '
                      'lista con una connessione attiva per averli anche offline.',
                )
              : ErrorState(onRetry: () => ref.invalidate(adminContractsProvider)),
          data: (data) => _ContractListBody(rows: data),
        ),
      ),
      floatingActionButton: CapabilityGate(
        capability: 'contratti.contract.write',
        child: Padding(
          // navClearance alone, not minus navGap — see admin_cantiere_list_screen.dart's comment
          // on this same change.
          padding: EdgeInsets.only(bottom: context.navClearance),
          child: AppFab(
            tooltip: 'Nuovo contratto',
            onPressed: () => context.push('/altro/contratti/nuovo'),
          ),
        ),
      ),
    );
  }
}

class _ContractListBody extends ConsumerStatefulWidget {
  const _ContractListBody({required this.rows});

  final ContractListRows rows;

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
    final contracts = widget.rows.rows;
    final filtered = contracts.where((c) {
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
          if (widget.rows.fromMirror && contracts.isNotEmpty)
            SliverToBoxAdapter(
              child: const MirrorNotice(what: 'contratti'),
            ),
          if (contracts.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: LucideIcons.fileSignature,
                title: 'Nessun contratto',
                body: 'Crea un nuovo contratto con il pulsante +.',
              ),
            )
          else if (filtered.isEmpty)
            // A search with no matches is a different situation from having no contracts at
            // all — the "create one" prompt above doesn't apply here.
            SliverToBoxAdapter(
              child: EmptyState(
                icon: LucideIcons.fileSignature,
                title: 'Nessun risultato',
                body: 'Nessun contratto corrisponde alla ricerca.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
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
                  onTap: () => context.push('/altro/contratti/${contract['id']}', extra: contract),
                );
              }, childCount: filtered.length),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
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
      leading: const RowIconTile(icon: LucideIcons.fileSignature),
      title: name,
      subtitle: customerName,
      meta: isActive ? null : const StatusPill(stato: 'Inattivo', small: true),
      showDivider: !isLast,
      onTap: onTap,
    );
  }
}
