// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/vetro_card.dart';
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
      body: SafeArea(
        child: locationAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorState(onRetry: () => ref.invalidate(adminLocationDetailProvider(locationId))),
          data: (location) {
            if (location == null) {
              return const UnavailableState(
                icon: LucideIcons.mapPin,
                titolo: 'Sede non disponibile',
                motivo:
                    "L'elenco sedi non è ancora sincronizzato sul "
                    'dispositivo, quindi questa sede non può essere '
                    'letta dalla cache locale anche se esiste sul server.',
              );
            }
            return _LocationDetailBody(location: location, locationId: locationId);
          },
        ),
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
          child: ScreenHeader(title: location.name, subtitle: location.city ?? '', showBack: true),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: VetroCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Column(
                children: [
                  KeyVal(label: 'Nome', value: location.name),
                  KeyVal(label: 'Città', value: location.city ?? '—'),
                  KeyVal(label: 'Indirizzo', value: location.address ?? '—'),
                  KeyVal(label: 'CAP', value: location.postalCode ?? '—'),
                  KeyVal(label: 'Telefono', value: location.phone ?? '—'),
                  if (location.latitude != null && location.longitude != null)
                    KeyVal(
                      label: 'Coordinate',
                      value: '${location.latitude}, ${location.longitude}',
                    ),
                  KeyVal(
                    label: 'Note',
                    value: location.notes?.isNotEmpty == true ? location.notes! : '—',
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
