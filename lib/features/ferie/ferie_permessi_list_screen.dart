// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_rack.dart';
import '../../core/utils/offline_guard.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ferie/absence_request_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

const Set<int> _kCancellable = {0, 1}; // Pending, Approved

/// Self-service AbsenceRequest history. Online-only, no-Drift-cache architecture (see
/// AbsenceRequestApiClient's own file doc).
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
    // Vetro chrome via the shared helper, not a hand-built AlertDialog — same as
    // rapportini_list_screen.dart's own delete confirmation.
    final confirmed = await confirmDeleteDialog(
      context,
      title: 'Annullare la richiesta?',
      message: 'La richiesta verrà annullata e non potrà più essere ripristinata.',
      confirmLabel: 'Annulla richiesta',
    );
    if (!confirmed) return false;
    if (!mounted) return false;

    // The sibling create flow (ferie_permessi_form_screen.dart's own _save) already guards its
    // write with this; cancelling one skipped it.
    if (!ensureOnlineOrWarn(context, ref)) return false;

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
      meta: !_cancellable
          ? AppBadge(label: absenceStatusLabel(widget.item.status))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBadge(label: absenceStatusLabel(widget.item.status)),
                // A swipe is the only way a mouse/keyboard/TalkBack/VoiceOver user cannot
                // perform — this button reaches the exact same cancel path (_confirmCancel) so
                // both ways to cancel a request agree on what "cancel" does, not just on how you
                // trigger it. Same fix as rapportini_list_screen.dart's own delete button.
                IconButton(
                  icon: Icon(LucideIcons.x, size: 18, color: context.colors.inkMuted),
                  tooltip: 'Annulla richiesta',
                  onPressed: () => _confirmCancel(),
                ),
              ],
            ),
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
