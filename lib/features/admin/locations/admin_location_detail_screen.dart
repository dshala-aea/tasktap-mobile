// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Single location by id from Drift cache.
final adminLocationDetailProvider = StreamProvider.autoDispose.family<Location?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.locations)..where((l) => l.id.equals(id))).watchSingleOrNull();
});

/// Admin location detail — read-only with edit FAB.
class AdminLocationDetailScreen extends ConsumerWidget {
  const AdminLocationDetailScreen({super.key, required this.locationId});

  final String locationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(adminLocationDetailProvider(locationId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/sedi/$locationId/modifica');
          },
        ),
      ),
      body: locationAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (location) {
          if (location == null) {
            return const Center(child: Text('Sede non trovata'));
          }
          return _LocationDetailBody(location: location, locationId: locationId);
        },
      ),
    );
  }
}

class _LocationDetailBody extends StatelessWidget {
  const _LocationDetailBody({required this.location, required this.locationId});

  final Location location;
  final String locationId;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: location.name,
            subtitle: location.city ?? '',
            showBack: true,
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, size: 20),
                itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Modifica'))],
                onSelected: (v) {
                  if (v == 'edit') {
                    context.push('/altro/sedi/$locationId/modifica');
                  }
                },
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Nome', value: location.name),
                _InfoRow(label: 'Città', value: location.city ?? '—'),
                _InfoRow(label: 'Indirizzo', value: location.address ?? '—'),
                _InfoRow(label: 'CAP', value: location.postalCode ?? '—'),
                _InfoRow(label: 'Telefono', value: location.phone ?? '—'),
                _InfoRow(
                  label: 'Note',
                  value: location.notes?.isNotEmpty == true ? location.notes! : '—',
                ),
              ],
            ),
          ),
        ),

        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: context.colors.inkMuted, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: context.colors.ink),
          ),
        ],
      ),
    );
  }
}
