// dart format width=100
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// All schedules from Drift cache, ordered by date desc.
final adminSchedulesProvider = StreamProvider.autoDispose<List<Schedule>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.schedules)..orderBy([(s) => OrderingTerm.desc(s.activityDate)])).watch();
});

/// Admin schedule list — filterable by date range.
class AdminScheduleListScreen extends StatefulWidget {
  const AdminScheduleListScreen({super.key});

  @override
  State<AdminScheduleListScreen> createState() => _AdminScheduleListScreenState();
}

class _AdminScheduleListScreenState extends State<AdminScheduleListScreen> {
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
        child: _AdminScheduleListBody(
          query: _query,
          searchCtrl: _searchCtrl,
          onQueryChanged: (q) => setState(() => _query = q),
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          tooltip: 'Nuova pianificazione',
          onPressed: () => context.push('/altro/pianificazioni/nuova'),
        ),
      ),
    );
  }
}

class _AdminScheduleListBody extends ConsumerWidget {
  const _AdminScheduleListBody({
    required this.query,
    required this.searchCtrl,
    required this.onQueryChanged,
  });

  final String query;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(adminSchedulesProvider);
    final allSchedules = schedulesAsync.valueOrNull ?? [];

    final filtered = allSchedules.where((s) {
      if (query.isEmpty) return true;
      return s.title.toLowerCase().contains(query.toLowerCase());
    }).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(syncProvider.notifier).performSync(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'Pianificazioni',
              subtitle: '${filtered.length} totali',
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
          if (schedulesAsync.isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xxxl),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: LucideIcons.calendarDays,
                title: 'Nessuna pianificazione',
                body: 'Crea una nuova pianificazione con il pulsante +.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                final schedule = filtered[i];
                final dateLabel = DateFormat(
                  'EEE d MMM HH:mm',
                  'it',
                ).format(schedule.activityDate.toLocal());
                return _AdminScheduleRow(
                  schedule: schedule,
                  dateLabel: dateLabel,
                  isLast: i == filtered.length - 1,
                );
              }, childCount: filtered.length),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }
}

class _AdminScheduleRow extends StatelessWidget {
  const _AdminScheduleRow({required this.schedule, required this.dateLabel, required this.isLast});

  final Schedule schedule;
  final String dateLabel;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: context.colors.bg3,
          borderRadius: AppRack.insetShape,
        ),
        child: Icon(LucideIcons.calendarDays, size: 20, color: context.colors.inkMuted),
      ),
      title: schedule.title.isNotEmpty ? schedule.title : 'Intervento',
      subtitle: dateLabel,
      meta: Icon(LucideIcons.chevronRight, size: 16, color: context.colors.inkMuted),
      showDivider: !isLast,
      onTap: () => context.push('/altro/pianificazioni/${schedule.id}'),
    );
  }
}
