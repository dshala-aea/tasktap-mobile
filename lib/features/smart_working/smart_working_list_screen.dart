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
import '../../data/entitlements/entitlement_providers.dart' show refreshEntitlements;
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
        // A failed refresh is not a reason to throw away rows the technician can already read: the
        // toast under the list says the update failed, and what was on screen stays. Only a screen
        // that never had an answer gets the error card. (`loaded` is non-null exactly when a
        // previous data value survived into this error state.)
        error: (_, _) => loaded == null
            ? ErrorState(onRetry: () => ref.invalidate(mySmartWorkingRequestsProvider))
            : _SmartWorkingListBody(items: loaded),
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
      // `mySmartWorkingRequestsProvider` throws when the server cannot be reached, and
      // `RefreshIndicator` does not catch the future it is handed: an uncaught rejection here is an
      // unhandled async error, and the user is told nothing. Say it with the shared toast instead —
      // the rows stay on screen (see the parent's error branch), the spinner stops, and the failure
      // is not silent.
      onRefresh: () async {
        try {
          // The result is used: awaiting it is the point — the spinner must last until the server
          // answers, and the rejection is caught below. `@useResult` cannot see an `await`.
          // ignore: unused_result
          await ref.refresh(mySmartWorkingRequestsProvider.future);
        } catch (_) {
          if (!context.mounted) return;
          showAppToast(
            context,
            message: 'Impossibile aggiornare. Riprova.',
            tone: ToastTone.error,
          );
        }
      },
      child: CustomScrollView(
        // Without this the empty state (shorter than the viewport) cannot be dragged at all, so
        // pull-to-refresh silently does nothing exactly when the technician wants to re-ask the
        // server. Same trap and fix as calendario_screen.dart's own list.
        physics: const AlwaysScrollableScrollPhysics(),
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
  /// True from the confirm tap to the server's answer. The control is replaced while it is set, so
  /// a second confirm cannot re-POST a cancel that already succeeded and stack an error toast on
  /// top of a success.
  bool _busy = false;

  bool get _cancellable => _kCancellableSmartWorkingStatuses.contains(widget.item.status);

  Future<void> _confirmCancel() async {
    if (_busy) return;

    final confirmed = await confirmDeleteDialog(
      context,
      title: 'Annullare la richiesta?',
      message: 'La richiesta di smart working verrà annullata e non potrà più essere ripristinata.',
      confirmLabel: 'Annulla richiesta',
    );
    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _busy = true);

    // Cancelling is a server-side state change with no local mirror (see this file's own doc);
    // refuse offline before the round trip rather than after a confusing Dio failure.
    if (!ensureOnlineOrWarn(context, ref)) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    try {
      await ref.read(smartWorkingRequestApiClientProvider).cancel(widget.item.id);
    } catch (e) {
      // The screen may be gone by now (`IconButton.onPressed` does not await this future, so an
      // error escaping here would surface as an unhandled async error).
      if (!mounted) return;
      showAppToast(
        context,
        // `_guarded` turns a 400's Italian `detail` into [SmartWorkingValidationError] for cancel
        // too. That text is the whole explanation (a row that went stale while the screen sat
        // open says "already decided"), where the generic line tells the technician to retry
        // something that can never succeed.
        message: e is SmartWorkingValidationError
            ? e.detail
            : 'Impossibile annullare la richiesta. Riprova.',
        tone: ToastTone.error,
      );
      setState(() => _busy = false);
      return;
    }

    // Using `ref` after an await on a disposed widget throws; the technician may have popped the
    // screen while the POST was in flight.
    if (!mounted) return;
    ref.invalidate(mySmartWorkingRequestsProvider);

    // A cancelled request can name TODAY, and `smartWorkingTodayProvider` is memory-only: without
    // re-asking `/auth/me` the timbra chip (and Home's punch prompt) would keep claiming an
    // approved remote day the technician just withdrew, until the next app resume. Same helper the
    // regular entitlement refresh uses, so the two surfaces agree on every path where this row is
    // still mounted — which is the normal one, since the list keeps cancelled rows and this row's
    // element survives the refetch.
    //
    // The exception is this row's own disposal during the `/auth/me` round trip (the technician
    // popped the screen): the helper invalidates through this row's `ref`, so its `invalidate`
    // would throw, and the swallow below would hide that the answer was never refreshed. The chip
    // is then stale until the next resume — the same tolerated residual as a warm app resumed
    // across midnight (a stale `true` costs one refused punch with a visible message; a stale
    // `false` would cost the day's hours, and this path can only produce the former). Fixing it
    // properly means refreshing off the container rather than a widget ref.
    try {
      await refreshEntitlements(ref);
    } catch (_) {
      // The cancel itself succeeded; a failed /auth/me refresh is not a cancel failure and must not
      // be reported as one.
    }
    if (mounted) setState(() => _busy = false);
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
                // withdraw a request at all. While the cancel is in flight the button gives way to
                // a spinner of the same footprint, so it cannot be tapped twice.
                if (_busy)
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
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
