// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_rack.dart';
import '../../core/utils/offline_guard.dart';
import '../../core/widgets/widgets.dart';
import '../../data/smart_working/smart_working_request_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Statuses the server still lets the technician withdraw from.
///
/// Pending needs no explanation; Approved is deliberate — "yes, but I am in the office after all"
/// is a change of plan the technician owns, and the backend accepts the cancel. Rejected and
/// Cancelled are both finished states and offer nothing.
const Set<int> _kCancellableSmartWorkingStatuses = {0, 1};

/// The technician's own smart-working requests.
///
/// A request is a MARKER for one or more remote days, never hours (see
/// `SmartWorkingRequestApiClient`'s file doc): this screen shows the civil-date window and the
/// shared absence-status label, and computes nothing. Filing and cancelling are online-only —
/// there is no local mirror of this entity, so a failed read says so instead of falling back to an
/// empty list (which would read as "you never asked").
class SmartWorkingListScreen extends ConsumerWidget {
  const SmartWorkingListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(mySmartWorkingRequestsProvider);
    final loaded = requestsAsync.valueOrNull;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: 'Smart working',
        // Only a loaded, non-empty answer has a count to state. A failed read has none, and "0
        // richieste" over an error card would be a claim the screen cannot make.
        subtitle: loaded == null || loaded.isEmpty ? null : '${loaded.length} richieste',
      ),
      body: requestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorState(onRetry: () => ref.invalidate(mySmartWorkingRequestsProvider)),
        data: (items) => _SmartWorkingListBody(items: items),
      ),
      floatingActionButton: Padding(
        // navClearance alone, not minus navGap — same as ferie_permessi_list_screen.dart.
        padding: EdgeInsets.only(bottom: context.navClearance),
        child: AppFab(
          tooltip: 'Nuova richiesta',
          onPressed: () => context.push('${AppRoutes.altroSmartWorking}/nuovo'),
        ),
      ),
    );
  }
}

class _SmartWorkingListBody extends ConsumerWidget {
  const _SmartWorkingListBody({required this.items});

  final List<SmartWorkingRequestDto> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.refresh(mySmartWorkingRequestsProvider.future),
      child: CustomScrollView(
        slivers: [
          if (items.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: LucideIcons.laptop,
                title: 'Nessuna richiesta',
                body: 'Invia una nuova richiesta di smart working con il pulsante +.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _SmartWorkingRow(item: items[i]),
                childCount: items.length,
              ),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }
}

class _SmartWorkingRow extends ConsumerStatefulWidget {
  const _SmartWorkingRow({required this.item});

  final SmartWorkingRequestDto item;

  @override
  ConsumerState<_SmartWorkingRow> createState() => _SmartWorkingRowState();
}

class _SmartWorkingRowState extends ConsumerState<_SmartWorkingRow> {
  bool get _cancellable => _kCancellableSmartWorkingStatuses.contains(widget.item.status);

  Future<void> _confirmCancel() async {
    final confirmed = await confirmDeleteDialog(
      context,
      title: 'Annullare la richiesta?',
      message: 'La richiesta di smart working verrà annullata e non potrà più essere ripristinata.',
      confirmLabel: 'Annulla richiesta',
    );
    if (!confirmed) return;
    if (!mounted) return;

    // Cancelling is a server-side state change with no local mirror (see this file's own doc);
    // refuse offline before the round trip rather than after a confusing Dio failure.
    if (!ensureOnlineOrWarn(context, ref)) return;

    try {
      await ref.read(smartWorkingRequestApiClientProvider).cancel(widget.item.id);
      ref.invalidate(mySmartWorkingRequestsProvider);
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Impossibile annullare la richiesta. Riprova.',
          tone: ToastTone.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final reason = item.reason?.trim();

    // The window the request names, in the same Italian prose every other date in this app uses
    // (`ferie_permessi_list_screen.dart`'s own subtitle). `startDate`/`endDate` are
    // `DateTime.utc(y, m, d)` civil-date labels, and `DateFormat.format` reads THAT INSTANCE's own
    // y/m/d fields — it does not convert the zone. Never "fix" this with `.toLocal()`: that would
    // show the previous day west of UTC, and a smart-working marker naming a day early is exactly
    // the mistake this screen cannot afford. No duration is computed — a smart-working request is
    // a marker for a remote day, not a timesheet.
    final start = DateFormat('d MMM', 'it').format(item.startDate);
    final end = DateFormat('d MMM', 'it').format(item.endDate);

    return ListRow(
      leading: const RowIconTile(icon: LucideIcons.laptop, color: AppColors.Y),
      title: '$start – $end',
      subtitle: reason == null || reason.isEmpty ? null : reason,
      meta: _cancellable
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(stato: item.statusLabel),
                // Same reasoning as ferie_permessi_list_screen.dart's cancel button: the action is
                // a real button (not only a gesture) so mouse/keyboard/TalkBack/VoiceOver users can
                // withdraw a request at all.
                IconButton(
                  icon: Icon(LucideIcons.x, size: 18, color: context.colors.inkMuted),
                  tooltip: 'Annulla richiesta',
                  onPressed: _confirmCancel,
                ),
              ],
            )
          : StatusPill(stato: item.statusLabel),
    );
  }
}
