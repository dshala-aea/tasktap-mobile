// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';

/// Single cantiere by id from Drift cache.
final adminCantiereDetailProvider =
    StreamProvider.autoDispose.family<CantieriData?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.cantieri)..where((c) => c.id.equals(id)))
      .watchSingleOrNull();
});

/// Admin cantiere detail — read-only with edit FAB.
class AdminCantiereDetailScreen extends ConsumerWidget {
  const AdminCantiereDetailScreen({super.key, required this.cantiereId});

  final String cantiereId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantiereAsync =
        ref.watch(adminCantiereDetailProvider(cantiereId));

    return Scaffold(
      backgroundColor: AppColors.BG2,
      floatingActionButton: AppFab(
        icon: LucideIcons.pencil,
        tooltip: 'Modifica',
        onPressed: () async {
          await context.push<bool>('/altro/cantieri/$cantiereId/modifica');
        },
      ),
      body: cantiereAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (cantiere) {
          if (cantiere == null) {
            return const UnavailableState(
              titolo: 'Cantiere non disponibile',
              motivo: "L'elenco cantieri non è ancora sincronizzato sul "
                  'dispositivo, quindi questo cantiere non può essere '
                  'letto dalla cache locale anche se esiste sul server.',
            );
          }
          return _CantiereDetailBody(
            cantiere: cantiere,
            cantiereId: cantiereId,
          );
        },
      ),
    );
  }
}

class _CantiereDetailBody extends StatelessWidget {
  const _CantiereDetailBody({
    required this.cantiere,
    required this.cantiereId,
  });

  final CantieriData cantiere;
  final String cantiereId;

  @override
  Widget build(BuildContext context) {
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
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, size: 20),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Modifica'),
                  ),
                ],
                onSelected: (v) {
                  if (v == 'edit') {
                    context.push('/altro/cantieri/$cantiereId/modifica');
                  }
                },
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Nome', value: cantiere.name),
                _InfoRow(label: 'Città', value: cantiere.city ?? '—'),
                _InfoRow(label: 'Indirizzo', value: cantiere.address ?? '—'),
                _InfoRow(
                    label: 'CAP', value: cantiere.postalCode ?? '—'),
                _InfoRow(label: 'Inizio', value: startLabel),
                _InfoRow(label: 'Fine', value: endLabel),
                _InfoRow(
                    label: 'Note',
                    value: cantiere.notes?.isNotEmpty == true
                        ? cantiere.notes!
                        : '—'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.MUTED,
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}
