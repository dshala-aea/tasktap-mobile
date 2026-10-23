// dart format width=100
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/utils/error_message.dart' show isTransportOrServerFault;
import '../../../core/widgets/widgets.dart';
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../ticket/ticket_detail_api_client.dart' show TicketDetailOfflineException;
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/status_colors.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Filter options for the admin report list.
enum _ReportFilter { tutti, bozza, inviato, controllato, fatturato }

extension _ReportFilterLabel on _ReportFilter {
  String get label => switch (this) {
    _ReportFilter.tutti => 'Tutti',
    _ReportFilter.bozza => 'Bozza',
    _ReportFilter.inviato => 'Inviato',
    _ReportFilter.controllato => 'Controllato',
    _ReportFilter.fatturato => 'Fatturato',
  };

  String? get statusMatch => switch (this) {
    _ReportFilter.tutti => null,
    _ReportFilter.bozza => 'Bozza',
    _ReportFilter.inviato => 'Inviato',
    _ReportFilter.controllato => 'Controllato',
    _ReportFilter.fatturato => 'Fatturato',
  };
}

/// Admin report list — shows all tenant reports from backend API.
class AdminReportListScreen extends StatefulWidget {
  const AdminReportListScreen({super.key});

  @override
  State<AdminReportListScreen> createState() => _AdminReportListScreenState();
}

class _AdminReportListScreenState extends State<AdminReportListScreen> {
  _ReportFilter _filter = _ReportFilter.tutti;
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
        child: _AdminReportListBody(
          filter: _filter,
          query: _query,
          searchCtrl: _searchCtrl,
          onFilterChanged: (f) => setState(() => _filter = f),
          onQueryChanged: (q) => setState(() => _query = q),
        ),
      ),
    );
  }
}

class _AdminReportListBody extends ConsumerWidget {
  const _AdminReportListBody({
    required this.filter,
    required this.query,
    required this.searchCtrl,
    required this.onFilterChanged,
    required this.onQueryChanged,
  });

  final _ReportFilter filter;
  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<_ReportFilter> onFilterChanged;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statoFilter = StatoFilter(filter.statusMatch);
    final reportsAsync = ref.watch(adminReportsProvider(statoFilter));

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminReportsProvider(statoFilter).future),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'Rapportini',
              subtitle: 'Vista amministratore',
              showBack: true,
            ),
          ),
          SliverToBoxAdapter(
            child: AppSearchBar(
              controller: searchCtrl,
              hint: 'Cerca per titolo…',
              onChanged: onQueryChanged,
            ),
          ),
          // ── Filter chips ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                0,
                AppSpacing.pagePadding,
                AppSpacing.md,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _ReportFilter.values.map((f) {
                    return Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: AppChip(
                        label: f.label,
                        active: filter == f,
                        onTap: () => onFilterChanged(f),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          // ── Report list ──────────────────────────────────────────────────
          reportsAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xxxl),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: e is TicketDetailOfflineException
                  ? const UnavailableState(
                      icon: LucideIcons.fileText,
                      titolo: 'Rapportini non disponibili offline',
                      motivo:
                          'Questo dispositivo non ha ancora scaricato i rapportini. Apri questa '
                          'lista con una connessione attiva per averli anche offline.',
                    )
                  : ErrorState(
                      onRetry: () => ref.invalidate(adminReportsProvider(statoFilter)),
                    ),
            ),
            data: (data) {
              final reports = data.rows;
              // Client-side query filter
              final filtered = reports.where((r) {
                if (query.isEmpty) return true;
                final title = (r['title'] as String? ?? '').toLowerCase();
                return title.contains(query.toLowerCase());
              }).toList();

              if (filtered.isEmpty) {
                return SliverToBoxAdapter(
                  child: EmptyState(
                    icon: LucideIcons.fileText,
                    title: 'Nessun rapportino',
                    body: 'Non ci sono rapportini per questo filtro.',
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  // The notice rides the first row so it scrolls with the list it describes
                  // instead of sitting above it as a header.
                  if (data.fromMirror && i == 0) {
                    return Column(
                      children: [
                        const MirrorNotice(what: 'rapportini'),
                        _AdminReportRow(report: filtered[i], isLast: filtered.length == 1),
                      ],
                    );
                  }
                  final report = filtered[i];
                  return _AdminReportRow(report: report, isLast: i == filtered.length - 1);
                }, childCount: filtered.length),
              );
            },
          ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }
}

/// The report list's rows, plus where they came from.
///
/// [fromMirror] drives [MirrorNotice]. It matters more here than on the other lists: the mirror
/// holds what *this device* synced, which for a technician is their own rapportini, so a mirrored
/// list under an "administrator view" header is a narrower set than the header suggests.
class ReportListRows {
  const ReportListRows(this.rows, {required this.fromMirror});

  final List<Map<String, dynamic>> rows;
  final bool fromMirror;
}

/// Provider that fetches reports from backend API, falling back to the synced mirror.
///
/// Same shape as the contract and asset lists: server-first when online, mirror on transport /
/// 5xx / 408 / 429, 4xx rethrown. The stato filter applies in both paths — the mirror stores the
/// `ReportStatoEnum` *name* in `DraftReports.stato`, which is what the server sends on the wire,
/// so the same chip value filters both.
final adminReportsProvider = FutureProvider.autoDispose
    .family<ReportListRows, StatoFilter>((ref, filter) async {
      Future<ReportListRows> fromMirror() async {
        final db = ref.watch(appDatabaseProvider);
        final query = db.select(db.draftReports);
        final stato = filter.value;
        if (stato != null) {
          query.where((r) => r.stato.equals(stato));
        }
        query.orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
        final rows = await query.get();
        if (rows.isEmpty && await db.getLastSync() == null) {
          throw const TicketDetailOfflineException();
        }
        return ReportListRows([
          for (final r in rows)
            {
              'id': r.id,
              'title': r.title,
              'ticketId': r.ticketId,
              'cantiereId': r.cantiereId,
              'stato': r.stato,
              // Re-stamped to UTC: the row formats these into local time, and Drift hands a
              // DateTimeColumn back as a LOCAL-kind instant.
              'createdAt': r.createdAt.toUtc().toIso8601String(),
              'isAiAssisted': r.isAiAssisted,
            },
        ], fromMirror: true);
      }

      if (ref.watch(isOnlineProvider)) {
        try {
          return ReportListRows(
            await ref.watch(adminApiClientProvider).fetchReports(stato: filter.value),
            fromMirror: false,
          );
        } catch (e) {
          if (!isTransportOrServerFault(e)) rethrow;
        }
      }
      return fromMirror();
    });

/// Simple wrapper for the stato filter value.
class StatoFilter {
  const StatoFilter(this.value);
  final String? value;
}

class _AdminReportRow extends StatelessWidget {
  const _AdminReportRow({required this.report, required this.isLast});

  final Map<String, dynamic> report;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final title = report['title'] as String? ?? '—';
    final stato = report['stato'] as String? ?? 'Bozza';
    final createdAt = report['createdAt'] as String?;
    final dateLabel = createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm', 'it').format(DateTime.parse(createdAt).toLocal())
        : '—';

    return ListRow(
      leading: _StatoIcon(stato: stato),
      title: title,
      subtitle: dateLabel,
      meta: StatusPill(stato: stato, small: true),
      showDivider: !isLast,
      onTap: () => context.push('/altro/rapportini-admin/${report['id']}', extra: report),
    );
  }
}

class _StatoIcon extends StatelessWidget {
  const _StatoIcon({required this.stato});

  final String stato;

  @override
  Widget build(BuildContext context) {
    // Only the glyph is decided here. The colour comes from `status_colors.dart`, the same source
    // the StatusPill on this very row reads — this switch used to carry its own blue, green and
    // violet, so the icon and the pill next to it disagreed about what "Inviato" looks like.
    final icon = switch (stato) {
      'Bozza' => LucideIcons.fileEdit,
      'Inviato' => LucideIcons.send,
      'Controllato' => LucideIcons.checkCircle,
      'Fatturato' => LucideIcons.receipt,
      _ => LucideIcons.fileText,
    };
    final color = statusColor(context, stato).foreground;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRack.insetShape,
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}
