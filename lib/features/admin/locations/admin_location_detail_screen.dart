// dart format width=100
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/router/app_router.dart' show AppRoutes;
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/time/business_time.dart' show formatWorkDate;
import '../../../core/widgets/detail/detail_facts_grid.dart';
import '../../../core/widgets/detail/detail_hero.dart';
import '../../../core/widgets/detail/detail_link_row.dart';
import '../../../core/widgets/detail/detail_scaffold.dart';
import '../../../core/widgets/detail/detail_section.dart';
import '../../../core/widgets/geo_map_card.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/entitlements/entitlement_providers.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_freshness_provider.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart'
    show customerByIdProvider, locationGeocodedLocationProvider;
import '../../clienti/clienti_providers.dart' show customerContactsProvider;
import '../../ticket/ticket_providers.dart' show ticketStatusMapProvider;

/// Single location by id from Drift cache.
final adminLocationDetailProvider = StreamProvider.autoDispose.family<Location?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.locations)..where((l) => l.id.equals(id))).watchSingleOrNull();
});

/// Contracts filed against this sede, from the local mirror the sync fills — never a network read.
final _locationContractsProvider = StreamProvider.autoDispose.family<List<Contract>, String>((
  ref,
  locationId,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.contracts)
        ..where((c) => c.locationId.equals(locationId))
        ..orderBy([(c) => OrderingTerm.desc(c.isActive), (c) => OrderingTerm.asc(c.endDate)]))
      .watch();
});

/// Tickets/interventi at this sede, newest first, from the same local mirror.
final _locationTicketsProvider = StreamProvider.autoDispose.family<List<Ticket>, String>((
  ref,
  locationId,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.tickets)
        ..where((t) => t.locationId.equals(locationId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});

/// The admin sede detail — the wave-0 summary shell: hero + `Modifica`, then Documenti & mappa,
/// Relazioni, Sintesi and Attività, in that order. Sections without local data are hidden.
class AdminLocationDetailScreen extends ConsumerWidget {
  const AdminLocationDetailScreen({super.key, required this.locationId});

  final String locationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(adminLocationDetailProvider(locationId));

    return locationAsync.when(
      loading: () => const DetailScaffold.loading(screenTitle: 'Sede'),
      error: (e, _) => DetailScaffold.unavailable(
        screenTitle: 'Sede',
        icon: LucideIcons.alertTriangle,
        title: 'Sede non disponibile',
        reason: 'Non è stato possibile leggere la sede salvata su questo telefono.',
        onRetry: () => ref.invalidate(adminLocationDetailProvider(locationId)),
      ),
      data: (location) {
        if (location == null) {
          // A missing row on a synced device is not "not downloaded": the sedi mirror is there and
          // simply has no such id — deleted, or no longer visible to this role.
          final neverSynced = ref.watch(hasSyncedAtLeastOnceProvider).value == false;
          return DetailScaffold.unavailable(
            screenTitle: 'Sede',
            icon: neverSynced ? LucideIcons.cloudOff : LucideIcons.mapPin,
            title: neverSynced ? 'Sede non disponibile' : 'Sede non trovata',
            reason: neverSynced
                ? "L'elenco sedi non è ancora sincronizzato sul dispositivo, quindi questa "
                      'sede non può essere letta dalla cache locale anche se esiste sul server.'
                : 'Questa sede non è presente sul telefono. Potrebbe essere stata eliminata o '
                      'non essere più visibile con il tuo ruolo.',
          );
        }
        return _LocationDetailBody(location: location, locationId: locationId);
      },
    );
  }
}

class _LocationDetailBody extends ConsumerWidget {
  const _LocationDetailBody({required this.location, required this.locationId});

  final Location location;
  final String locationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final customer = ref.watch(customerByIdProvider(location.customerId)).value;
    final contacts = ref.watch(customerContactsProvider(location.customerId)).value ?? const [];
    final contracts = ref.watch(_locationContractsProvider(locationId)).value ?? const [];
    final tickets = ref.watch(_locationTicketsProvider(locationId)).value ?? const [];
    final statusNames = ref.watch(ticketStatusMapProvider).value ?? const <int, String>{};

    final canWrite =
        ref
            .watch(cachedEntitlementProvider)
            .value
            ?.capabilities
            .contains('clienti.location.write') ??
        false;

    // Same joined-address shape the ticket/cantiere details already build — GeoMapCard's fallback
    // text and "Apri in Mappe" query both read from this string.
    final address = [
      location.address,
      location.city,
      location.postalCode,
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    final heroFacts = [
      if (customer != null && customer.companyName.isNotEmpty) customer.companyName,
      if (location.city != null && location.city!.isNotEmpty) location.city!,
      if (tickets.isNotEmpty)
        '${tickets.length} ${tickets.length == 1 ? 'intervento' : 'interventi'}',
    ];

    // Sintesi carries only what the hero does not: the street address, CAP, phone and free notes.
    final sintesiFacts = <DetailFact>[
      if (location.address != null && location.address!.isNotEmpty)
        DetailFact(label: 'Indirizzo', value: location.address!),
      if (location.postalCode != null && location.postalCode!.isNotEmpty)
        DetailFact(label: 'CAP', value: location.postalCode!),
      if (location.phone != null && location.phone!.isNotEmpty)
        DetailFact(label: 'Telefono', value: location.phone!),
    ];
    final hasNotes = location.notes != null && location.notes!.isNotEmpty;

    final relations = <_Relation>[
      if (customer != null)
        _Relation(
          title: 'Cliente',
          meta: customer.companyName,
          onTap: () => context.push(AppRoutes.clientiDetail(customer.id)),
        ),
      for (final contact in contacts)
        _Relation(
          title: contact.name,
          meta: [contact.role, contact.phone].where((v) => v != null && v.isNotEmpty).join(' · '),
        ),
      for (final contract in contracts)
        _Relation(
          title: contract.name,
          meta: _contractMeta(contract),
          onTap: () =>
              context.push('/altro/contratti/${contract.id}', extra: _contractExtra(contract)),
        ),
    ];

    final hasMap = address.isNotEmpty;

    return DetailScaffold(
      screenTitle: 'Sede',
      hero: DetailHeroData(
        variant: DetailHeroVariant.summary,
        kind: 'Summary · sede',
        kicker: 'Summary',
        kickerContext: 'sede',
        title: location.name,
        status: DetailStatus(
          label: location.isActive ? 'Attiva' : 'Inattiva',
          tone: location.isActive ? DetailStatusTone.good : DetailStatusTone.neutral,
        ),
        subtitle: heroFacts.isEmpty ? null : heroFacts.join(' · '),
        primaryAction: canWrite
            ? DetailAction(
                label: 'Modifica',
                onPressed: () async {
                  await context.push<bool>('/altro/sedi/$locationId/modifica');
                },
              )
            : null,
      ),
      sections: [
        DetailSectionData(
          title: 'Documenti & mappa',
          isEmpty: !hasMap,
          child: GeoMapCard(
            pointAsync: ref.watch(locationGeocodedLocationProvider(locationId)),
            address: address,
          ),
        ),
        DetailSectionData(
          title: 'Relazioni',
          isEmpty: relations.isEmpty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < relations.length; i++)
                DetailLinkRow(
                  title: relations[i].title,
                  meta: relations[i].onTap == null ? relations[i].meta : null,
                  trailing: relations[i].onTap == null
                      ? null
                      : _LinkTrailing(meta: relations[i].meta),
                  onTap: relations[i].onTap,
                  showDivider: i < relations.length - 1,
                ),
            ],
          ),
        ),
        DetailSectionData(
          title: 'Sintesi',
          isEmpty: sintesiFacts.isEmpty && !hasNotes,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sintesiFacts.isNotEmpty) DetailFactsGrid(facts: sintesiFacts),
              if (hasNotes) ...[
                if (sintesiFacts.isNotEmpty) const SizedBox(height: AppSpacing.md),
                Text(
                  'NOTE',
                  style: AppTextStyles.docCode.copyWith(
                    fontSize: 8,
                    letterSpacing: 0.64,
                    color: colors.inkMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  location.notes!,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 11.5,
                    height: 1.4,
                    color: colors.ink,
                  ),
                ),
              ],
            ],
          ),
        ),
        DetailSectionData(
          title: 'Attività',
          isEmpty: tickets.isEmpty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tickets.length; i++)
                DetailLinkRow(
                  title: tickets[i].title,
                  meta: _ticketMeta(tickets[i], statusNames),
                  onTap: () => context.push(AppRoutes.ticketDetailPath(tickets[i].id)),
                  showDivider: i < tickets.length - 1,
                ),
            ],
          ),
        ),
      ],
      onRefresh: () => refreshWithFeedback(context, ref),
    );
  }

  static String _contractMeta(Contract contract) {
    if (!contract.isActive) return 'Inattivo';
    final end = contract.endDate;
    if (end != null) {
      return 'Scade ${formatWorkDate(end, 'dd/MM/yyyy')}';
    }
    return 'Attivo';
  }

  /// The contract detail route still reads its row from `extra`; the mirror carries the list-shaped
  /// fields only, so absent ones stay absent rather than being guessed.
  static Map<String, dynamic> _contractExtra(Contract contract) => {
    'id': contract.id,
    'name': contract.name,
    'customerId': contract.customerId,
    'locationId': contract.locationId,
    'startDate': contract.startDate.toUtc().toIso8601String(),
    'endDate': contract.endDate?.toUtc().toIso8601String(),
    'isActive': contract.isActive,
    'numero': contract.numero,
    'codice': contract.codice,
    'externalId': contract.externalId,
  };

  static String _ticketMeta(Ticket ticket, Map<int, String> statusNames) {
    final date = formatWorkDate(ticket.createdAt, 'dd/MM/yyyy');
    final status = statusNames[ticket.statusId];
    return status == null || status.isEmpty ? date : '$date · $status';
  }
}

class _Relation {
  const _Relation({required this.title, this.meta, this.onTap});

  final String title;
  final String? meta;
  final VoidCallback? onTap;
}

/// The right-hand side of a tappable relation row: the mono meta plus the chevron that tells a
/// person the row opens something. Mirrors the schedule detail's own trailing widget.
class _LinkTrailing extends StatelessWidget {
  const _LinkTrailing({required this.meta});

  final String? meta;

  @override
  Widget build(BuildContext context) {
    final text = meta;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (text != null && text.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              text.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppTextStyles.docCode.copyWith(
                fontSize: 7.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
                color: context.colors.inkMuted,
              ),
            ),
          ),
        if (text != null && text.isNotEmpty) const SizedBox(width: 6),
        Icon(LucideIcons.chevronRight, size: 14, color: context.colors.inkMuted),
      ],
    );
  }
}
