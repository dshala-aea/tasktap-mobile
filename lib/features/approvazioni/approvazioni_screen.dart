// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_rack.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/offline_guard.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ferie/absence_request_api_client.dart';
import '../../data/smart_working/smart_working_request_api_client.dart';
import '../../data/sync/connectivity_provider.dart';
import '../../data/users/user_directory.dart';
import 'approval_request_card.dart';
import 'approvazioni_providers.dart';
import 'reject_reason_sheet.dart';

enum _ApprovalTab { assenze, smartWorking }

/// The approver's worklist: every pending ferie/permesso and smart-working request in the tenant.
///
/// Reachable only with `presenze.absence.approve` (the route guard enforces it). Online-only: there
/// is no mirror of other people's requests, so a failed read is an error state, never an empty
/// queue. The two tabs are independent; only the selected queue is fetched.
class ApprovazioniScreen extends ConsumerStatefulWidget {
  const ApprovazioniScreen({super.key, this.initialTab});

  /// `assenze` | `smart-working` from a notification deep link. Anything else opens the default.
  final String? initialTab;

  @override
  ConsumerState<ApprovazioniScreen> createState() => _ApprovazioniScreenState();
}

class _ApprovazioniScreenState extends ConsumerState<ApprovazioniScreen> {
  late _ApprovalTab _tab = widget.initialTab == 'smart-working'
      ? _ApprovalTab.smartWorking
      : _ApprovalTab.assenze;

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    // Read the selected queue for the header count only when online; offline, watching it would
    // issue the request the screen is about to say is impossible.
    final selected = online
        ? (_tab == _ApprovalTab.assenze
              ? ref.watch(absenceApprovalQueueProvider)
              : ref.watch(smartWorkingApprovalQueueProvider))
        : null;
    final count = selected?.valueOrNull?.length;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: 'Approvazioni',
        subtitle: count == null || count == 0 ? null : '$count in attesa',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.sm,
              AppSpacing.pagePadding,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Ferie e permessi'),
                  selected: _tab == _ApprovalTab.assenze,
                  onSelected: (_) => setState(() => _tab = _ApprovalTab.assenze),
                ),
                const SizedBox(width: AppSpacing.sm),
                ChoiceChip(
                  label: const Text('Smart working'),
                  selected: _tab == _ApprovalTab.smartWorking,
                  onSelected: (_) => setState(() => _tab = _ApprovalTab.smartWorking),
                ),
              ],
            ),
          ),
          Expanded(
            child: _tab == _ApprovalTab.assenze
                ? const _AbsenceQueue()
                : const _SmartWorkingQueue(),
          ),
        ],
      ),
    );
  }
}

class _AbsenceQueue extends ConsumerStatefulWidget {
  const _AbsenceQueue();

  @override
  ConsumerState<_AbsenceQueue> createState() => _AbsenceQueueState();
}

class _AbsenceQueueState extends ConsumerState<_AbsenceQueue> {
  final _busy = <String>{};

  void _refresh() {
    ref.invalidate(absenceApprovalQueueProvider);
    ref.invalidate(myAbsenceRequestsProvider);
  }

  Future<void> _approve(AbsenceRequestDto item, String name) async {
    if (_busy.contains(item.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Approvare la richiesta di $name?'),
        content: Text(_absenceSubtitle(item)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approva richiesta')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_busy.contains(item.id)) return;
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _busy.add(item.id));
    try {
      await ref.read(absenceRequestApiClientProvider).approve(item.id);
      _refresh();
      if (mounted) {
        showAppToast(context, message: 'Richiesta approvata.', tone: ToastTone.success);
      }
    } on AbsenceRequestValidationError catch (e) {
      _refresh();
      if (mounted) showAppToast(context, message: e.detail, tone: ToastTone.error);
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Impossibile approvare la richiesta. Riprova.',
          tone: ToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  Future<void> _reject(AbsenceRequestDto item, String name) async {
    if (_busy.contains(item.id)) return;
    if (!ensureOnlineOrWarn(context, ref)) return;

    await showRejectReasonSheet(
      context,
      title: 'Rifiuta la richiesta di $name',
      onSubmit: (reason) async {
        try {
          await ref.read(absenceRequestApiClientProvider).reject(item.id, reason: reason);
          _refresh();
          if (mounted) {
            showAppToast(context, message: 'Richiesta rifiutata.', tone: ToastTone.success);
          }
          return null;
        } on AbsenceRequestValidationError catch (e) {
          // The server answered and will answer the same way again: terminal. Close the sheet and
          // say why, rather than letting the approver retry a row that no longer exists.
          _refresh();
          if (mounted) showAppToast(context, message: e.detail, tone: ToastTone.error);
          return null;
        } catch (_) {
          return 'Impossibile rifiutare la richiesta. Riprova.';
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isOnlineProvider)) {
      return _OfflineState(provider: absenceApprovalQueueProvider);
    }

    final requests = ref.watch(absenceApprovalQueueProvider);
    final names = ref.watch(userNameByIdProvider).valueOrNull ?? const <String, String>{};

    return requests.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorState(
        onRetry: () => ref.invalidate(absenceApprovalQueueProvider),
      ),
      data: (items) => items.isEmpty
          ? const EmptyState(
              icon: LucideIcons.calendarX,
              title: 'Nessuna richiesta da approvare',
              body: 'Le nuove richieste di ferie e permessi compariranno qui.',
            )
          : ListView.builder(
              padding: EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: context.navClearance,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final name = names[item.requestedByUserId] ?? '—';
                return ApprovalRequestCard(
                  title: name,
                  subtitle: _absenceSubtitle(item),
                  reason: item.reason,
                  busy: _busy.contains(item.id),
                  onApprove: () => _approve(item, name),
                  onReject: () => _reject(item, name),
                );
              },
            ),
    );
  }
}

class _SmartWorkingQueue extends ConsumerStatefulWidget {
  const _SmartWorkingQueue();

  @override
  ConsumerState<_SmartWorkingQueue> createState() => _SmartWorkingQueueState();
}

class _SmartWorkingQueueState extends ConsumerState<_SmartWorkingQueue> {
  final _busy = <String>{};

  void _refresh() {
    ref.invalidate(smartWorkingApprovalQueueProvider);
    ref.invalidate(mySmartWorkingRequestsProvider);
  }

  Future<void> _approve(SmartWorkingRequestDto item, String name) async {
    if (_busy.contains(item.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Approvare la richiesta di $name?'),
        content: Text(_smartWorkingSubtitle(item)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approva richiesta')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_busy.contains(item.id)) return;
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _busy.add(item.id));
    try {
      await ref.read(smartWorkingRequestApiClientProvider).approve(item.id);
      _refresh();
      if (mounted) {
        showAppToast(context, message: 'Richiesta approvata.', tone: ToastTone.success);
      }
    } on SmartWorkingValidationError catch (e) {
      _refresh();
      if (mounted) showAppToast(context, message: e.detail, tone: ToastTone.error);
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          message: 'Impossibile approvare la richiesta. Riprova.',
          tone: ToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  Future<void> _reject(SmartWorkingRequestDto item, String name) async {
    if (_busy.contains(item.id)) return;
    if (!ensureOnlineOrWarn(context, ref)) return;

    await showRejectReasonSheet(
      context,
      title: 'Rifiuta la richiesta di $name',
      onSubmit: (reason) async {
        try {
          await ref.read(smartWorkingRequestApiClientProvider).reject(item.id, reason: reason);
          _refresh();
          if (mounted) {
            showAppToast(context, message: 'Richiesta rifiutata.', tone: ToastTone.success);
          }
          return null;
        } on SmartWorkingValidationError catch (e) {
          _refresh();
          if (mounted) showAppToast(context, message: e.detail, tone: ToastTone.error);
          return null;
        } catch (_) {
          return 'Impossibile rifiutare la richiesta. Riprova.';
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isOnlineProvider)) {
      return _OfflineState(provider: smartWorkingApprovalQueueProvider);
    }

    final requests = ref.watch(smartWorkingApprovalQueueProvider);
    final names = ref.watch(userNameByIdProvider).valueOrNull ?? const <String, String>{};

    return requests.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => ErrorState(
        onRetry: () => ref.invalidate(smartWorkingApprovalQueueProvider),
      ),
      data: (items) => items.isEmpty
          ? const EmptyState(
              icon: LucideIcons.laptop,
              title: 'Nessuna richiesta da approvare',
              body: 'Le nuove richieste di smart working compariranno qui.',
            )
          : ListView.builder(
              padding: EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: context.navClearance,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final name = names[item.requestedByUserId] ?? '—';
                return ApprovalRequestCard(
                  title: name,
                  subtitle: _smartWorkingSubtitle(item),
                  reason: item.reason,
                  busy: _busy.contains(item.id),
                  onApprove: () => _approve(item, name),
                  onReject: () => _reject(item, name),
                );
              },
            ),
    );
  }
}

class _OfflineState extends ConsumerWidget {
  const _OfflineState({required this.provider});

  final ProviderOrFamily provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return UnavailableState(
      icon: LucideIcons.wifiOff,
      titolo: 'Sei offline',
      motivo: 'Le richieste da approvare non sono disponibili senza connessione.',
      action: AppButton(
        label: 'Riprova',
        size: AppButtonSize.sm,
        fullWidth: false,
        onPressed: () => ref.invalidate(provider),
      ),
    );
  }
}

String _day(DateTime date) => DateFormat('d MMM', 'it').format(date);

String _absenceSubtitle(AbsenceRequestDto item) {
  final period = '${_day(item.startDate)} – ${_day(item.endDate)}';
  final start = _time(item.startTime);
  final end = _time(item.endTime);
  final window = start == null || end == null ? '' : ' · $start–$end';
  return '${absenceTypeLabel(item.type)} · $period$window';
}

String _smartWorkingSubtitle(SmartWorkingRequestDto item) =>
    'Smart working · ${_day(item.startDate)} – ${_day(item.endDate)}';

/// A `HH:MM:SS` wire time as `HH:MM`; null when absent or too short to read.
String? _time(String? raw) {
  if (raw == null || raw.length < 5) return null;
  return raw.substring(0, 5);
}
