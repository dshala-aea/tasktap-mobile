// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_rack.dart';
import '../../core/utils/offline_guard.dart';
import '../../core/widgets/widgets.dart';
import '../../data/trasferta/trasferta_request_api_client.dart';

/// The technician's own trasferte.
///
/// Online-only: there is no local mirror, so a failed or offline read says "serve la connessione"
/// instead of showing an empty list (which would read as "you never filed one").
class TrasfertaListScreen extends ConsumerWidget {
  const TrasfertaListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myTrasfertaRequestsProvider);
    final loaded = async.value;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: 'Trasferta',
        subtitle: loaded == null || loaded.isEmpty ? null : '${loaded.length} registrate',
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => loaded == null
            ? ErrorState(
                titolo: 'Serve la connessione',
                motivo: 'Le trasferte si leggono e si registrano solo online. Riprova con la rete.',
                onRetry: () => ref.invalidate(myTrasfertaRequestsProvider),
              )
            : _TrasfertaListBody(items: loaded),
        data: (items) => _TrasfertaListBody(items: items),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance),
        child: AppFab(
          tooltip: 'Nuova trasferta',
          onPressed: () => context.push('${AppRoutes.altroTrasferta}/nuovo'),
        ),
      ),
    );
  }
}

class _TrasfertaListBody extends ConsumerWidget {
  const _TrasfertaListBody({required this.items});

  final List<TrasfertaRequestDto> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        try {
          // ignore: unused_result
          await ref.refresh(myTrasfertaRequestsProvider.future);
        } catch (_) {
          if (!context.mounted) return;
          showAppToast(context, message: 'Impossibile aggiornare. Riprova.', tone: ToastTone.error);
        }
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (items.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: LucideIcons.mapPin,
                title: 'Nessuna trasferta',
                body: 'Registra il tempo di viaggio con il pulsante +.',
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _TrasfertaRow(item: items[i]),
                childCount: items.length,
              ),
            ),
          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }
}

class _TrasfertaRow extends ConsumerStatefulWidget {
  const _TrasfertaRow({required this.item});

  final TrasfertaRequestDto item;

  @override
  ConsumerState<_TrasfertaRow> createState() => _TrasfertaRowState();
}

class _TrasfertaRowState extends ConsumerState<_TrasfertaRow> {
  bool _busy = false;

  Future<void> _confirmCancel() async {
    if (_busy) return;
    final confirmed = await confirmDeleteDialog(
      context,
      title: 'Annullare la trasferta?',
      message: 'Le ore registrate per questa trasferta verranno rimosse dal giorno.',
      confirmLabel: 'Annulla trasferta',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    if (!ensureOnlineOrWarn(context, ref)) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    try {
      await ref.read(trasfertaRequestApiClientProvider).cancel(widget.item.id);
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: e is TrasfertaRuleError
            ? e.detail
            : 'Impossibile annullare la trasferta. Riprova.',
        tone: ToastTone.error,
      );
      setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    ref.invalidate(myTrasfertaRequestsProvider);
    setState(() => _busy = false);
  }

  /// `1,5 h` / `2 h` — Italian decimal comma, no trailing zero.
  static String _hoursLabel(double h) {
    final text = h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toString().replaceAll('.', ',');
    return '$text h';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final reason = item.reason?.trim();
    // `date` is a civil-date label (`DateTime.utc`): DateFormat reads its own y/m/d. Never toLocal.
    final day = DateFormat('EEE d MMM', 'it').format(item.date);
    final title = '$day · dalle ${item.startTime} · ${_hoursLabel(item.hours)}';

    return ListRow(
      leading: const RowIconTile(icon: LucideIcons.mapPin, color: AppColors.Y),
      title: title,
      subtitle: reason == null || reason.isEmpty ? null : reason,
      meta: item.cancellable
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(stato: item.statusLabel),
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
                    tooltip: 'Annulla trasferta',
                    onPressed: _confirmCancel,
                  ),
              ],
            )
          : StatusPill(stato: item.statusLabel),
    );
  }
}
