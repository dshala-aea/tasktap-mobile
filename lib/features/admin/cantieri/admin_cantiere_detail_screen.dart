// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Single cantiere by id from Drift cache.
final adminCantiereDetailProvider = StreamProvider.autoDispose.family<CantieriData?, String>((
  ref,
  id,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.cantieri)..where((c) => c.id.equals(id))).watchSingleOrNull();
});

/// Admin cantiere detail — read-only with edit FAB.
class AdminCantiereDetailScreen extends ConsumerWidget {
  const AdminCantiereDetailScreen({super.key, required this.cantiereId});

  final String cantiereId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantiereAsync = ref.watch(adminCantiereDetailProvider(cantiereId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/cantieri/$cantiereId/modifica');
          },
        ),
      ),
      body: cantiereAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorState(onRetry: () => ref.invalidate(adminCantiereDetailProvider(cantiereId))),
        data: (cantiere) {
          if (cantiere == null) {
            return const UnavailableState(
              titolo: 'Cantiere non disponibile',
              motivo:
                  "L'elenco cantieri non è ancora sincronizzato sul "
                  'dispositivo, quindi questo cantiere non può essere '
                  'letto dalla cache locale anche se esiste sul server.',
            );
          }
          return _CantiereDetailBody(cantiere: cantiere, cantiereId: cantiereId);
        },
      ),
    );
  }
}

/// Delete confirmation dialog + API call — mirrors `_deleteCustomer` in
/// admin_customer_detail_screen.dart (no shared confirm-dialog widget exists yet in this app).
Future<void> _deleteCantiere(BuildContext context, WidgetRef ref, String cantiereId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminare il cantiere?'),
      content: const Text(
        "L'eliminazione è definitiva. Interventi e log collegati non saranno più raggiungibili "
        'da qui.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(adminApiClientProvider).deleteCantiere(cantiereId);
    unawaited(ref.read(syncProvider.notifier).performSync());
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cantiere eliminato')));
      context.pop(true);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Impossibile eliminare. Riprova.'),
          backgroundColor: context.colors.red,
        ),
      );
    }
  }
}

class _CantiereDetailBody extends ConsumerWidget {
  const _CantiereDetailBody({required this.cantiere, required this.cantiereId});

  final CantieriData cantiere;
  final String cantiereId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startLabel = cantiere.startDate != null
        ? DateFormat('dd/MM/yyyy').format(cantiere.startDate!.toLocal())
        : '—';
    final endLabel = cantiere.endDate != null
        ? DateFormat('dd/MM/yyyy').format(cantiere.endDate!.toLocal())
        : '—';

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: cantiere.name,
            subtitle: cantiere.city ?? '',
            showBack: true,
            actions: [
              HeaderIconBtn(
                icon: LucideIcons.trash2,
                label: 'Elimina cantiere',
                glass: true,
                onTap: () => _deleteCantiere(context, ref, cantiereId),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Column(
                children: [
                  KeyVal(label: 'Nome', value: cantiere.name),
                  KeyVal(label: 'Città', value: cantiere.city ?? '—'),
                  KeyVal(label: 'Indirizzo', value: cantiere.address ?? '—'),
                  KeyVal(label: 'CAP', value: cantiere.postalCode ?? '—'),
                  KeyVal(label: 'Inizio', value: startLabel),
                  KeyVal(label: 'Fine', value: endLabel),
                  KeyVal(
                    label: 'Note',
                    value: cantiere.notes?.isNotEmpty == true ? cantiere.notes! : '—',
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
        ),

        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
      ],
    );
  }
}
