// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_rack.dart';
import '../../core/theme/app_vetro_palette.dart';
import '../../core/widgets/widgets.dart';
import '../../data/agenda/agenda_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// A technician's own quick-task list — separate from Schedule (`calendario/`), which is
/// dispatcher-assigned work. See the file doc in `agenda_api_client.dart` for why this reads and
/// writes online-only rather than through the Drift cache + sync queue most screens use.
class AgendaListScreen extends ConsumerWidget {
  const AgendaListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agendaAsync = ref.watch(agendaListProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: agendaAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(onRetry: () => ref.invalidate(agendaListProvider)),
          data: (items) => _AgendaListBody(items: items),
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          tooltip: 'Nuovo task',
          onPressed: () => context.push('/altro/agenda/nuovo'),
        ),
      ),
    );
  }
}

class _AgendaListBody extends ConsumerWidget {
  const _AgendaListBody({required this.items});

  final List<AgendaItemDto> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(agendaListProvider.future),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'Agenda',
              subtitle: items.isEmpty ? null : '${items.length} task',
              showBack: true,
            ),
          ),
          if (items.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: LucideIcons.calendarCheck,
                title: 'Nessun task in agenda',
                body: 'Aggiungi un task veloce con il pulsante +.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _AgendaRow(item: items[i]),
                childCount: items.length,
              ),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }
}

class _AgendaRow extends ConsumerStatefulWidget {
  const _AgendaRow({required this.item});

  final AgendaItemDto item;

  @override
  ConsumerState<_AgendaRow> createState() => _AgendaRowState();
}

class _AgendaRowState extends ConsumerState<_AgendaRow> {
  bool _busy = false;

  String get _subtitle {
    final item = widget.item;
    final dateLabel = DateFormat('d MMM', 'it').format(item.date);
    final timeLabel = item.timeStart != null ? ' · ${item.timeStart!.substring(0, 5)}' : '';
    return '$dateLabel$timeLabel';
  }

  Future<void> _complete() async {
    if (widget.item.isCompleted || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(agendaApiClientProvider).completeAgendaItem(widget.item.id);
      ref.invalidate(agendaListProvider);
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Impossibile completare il task. Riprova.',
          tone: ToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare il task?'),
        content: Text('"${widget.item.title}" verrà eliminato definitivamente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (confirmed != true) return false;

    try {
      await ref.read(agendaApiClientProvider).deleteAgendaItem(widget.item.id);
      ref.invalidate(agendaListProvider);
      return true;
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Impossibile eliminare il task. Riprova.',
          tone: ToastTone.error,
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Dismissible(
      key: ValueKey('agenda-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(LucideIcons.trash2, color: context.colors.red),
      ),
      confirmDismiss: (_) => _confirmDelete(),
      child: ListRow(
        leading: AppTappable(
          onTap: _complete,
          child: RowIconTile(
            icon: item.isCompleted ? LucideIcons.checkCircle2 : LucideIcons.circle,
            // context.vetro.tint, not the fixed AppVetroColors.tint — this row sits on the
            // normal flipping page ground, not a permanently-dark surface, so it needs the
            // theme-appropriate tint (the fixed light-mode value read lower-contrast in dark).
            color: item.isCompleted ? context.colors.green : context.vetro.tint,
          ),
        ),
        title: item.title,
        subtitle: _subtitle,
        meta: AppBadge(label: agendaPriorityLabel(item.priority)),
        onTap: () => context.push('/altro/agenda/${item.id}/modifica', extra: item),
      ),
    );
  }
}
