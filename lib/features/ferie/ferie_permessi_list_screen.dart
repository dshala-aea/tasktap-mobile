// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_rack.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ferie/absence_request_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

const Set<int> _kCancellable = {0, 1}; // Pending, Approved

/// Self-service AbsenceRequest history. Mirrors agenda_list_screen.dart's online-only,
/// no-Drift-cache architecture exactly (see AbsenceRequestApiClient's own file doc).
class FeriePermessiListScreen extends ConsumerWidget {
  const FeriePermessiListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(myAbsenceRequestsProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: requestsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(onRetry: () => ref.invalidate(myAbsenceRequestsProvider)),
          data: (items) => _FeriePermessiListBody(items: items),
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          tooltip: 'Nuova richiesta',
          onPressed: () => context.push('/altro/ferie/nuovo'),
        ),
      ),
    );
  }
}

class _FeriePermessiListBody extends ConsumerWidget {
  const _FeriePermessiListBody({required this.items});

  final List<AbsenceRequestDto> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(myAbsenceRequestsProvider.future),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: 'Ferie e Permessi',
              subtitle: items.isEmpty ? null : '${items.length} richieste',
              showBack: true,
            ),
          ),
          if (items.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: LucideIcons.calendarX,
                title: 'Nessuna richiesta',
                body: 'Invia una nuova richiesta con il pulsante +.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _FeriePermessiRow(item: items[i]),
                childCount: items.length,
              ),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }
}

class _FeriePermessiRow extends ConsumerStatefulWidget {
  const _FeriePermessiRow({required this.item});

  final AbsenceRequestDto item;

  @override
  ConsumerState<_FeriePermessiRow> createState() => _FeriePermessiRowState();
}

class _FeriePermessiRowState extends ConsumerState<_FeriePermessiRow> {
  String get _subtitle {
    final item = widget.item;
    final start = DateFormat('d MMM', 'it').format(item.startDate);
    final end = DateFormat('d MMM', 'it').format(item.endDate);
    return '$start – $end · ${absenceStatusLabel(item.status)}';
  }

  bool get _cancellable => _kCancellable.contains(widget.item.status);

  Future<bool> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annullare la richiesta?'),
        content: const Text('La richiesta verrà annullata e non potrà più essere ripristinata.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Chiudi')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Annulla richiesta'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    try {
      await ref.read(absenceRequestApiClientProvider).cancel(widget.item.id);
      ref.invalidate(myAbsenceRequestsProvider);
      return true;
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Impossibile annullare la richiesta. Riprova.',
          tone: ToastTone.error,
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = ListRow(
      leading: RowIconTile(
        icon: LucideIcons.calendarDays,
        color: AppColors.Y,
      ),
      title: absenceTypeLabel(widget.item.type),
      subtitle: _subtitle,
      meta: AppBadge(label: absenceStatusLabel(widget.item.status)),
    );

    if (!_cancellable) return row;

    return Dismissible(
      key: ValueKey('ferie-${widget.item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(LucideIcons.x, color: context.colors.red),
      ),
      confirmDismiss: (_) => _confirmCancel(),
      child: row,
    );
  }
}
