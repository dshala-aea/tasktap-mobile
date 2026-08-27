// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/vetro_card.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/clienti/cliente_overview_api_client.dart';
import '../../../data/sync/sync_service.dart';
import '../../clienti/clienti_providers.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin customer detail — shows all fields + edit FAB.
class AdminCustomerDetailScreen extends ConsumerWidget {
  const AdminCustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailProvider(customerId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.fabSafeBottom),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/clienti/$customerId/modifica');
          },
        ),
      ),
      body: SafeArea(
        child: customerAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorState(onRetry: () => ref.invalidate(customerDetailProvider(customerId))),
          data: (customer) {
            if (customer == null) {
              return const UnavailableState(
                icon: LucideIcons.users,
                titolo: 'Cliente non disponibile',
                motivo:
                    "L'elenco clienti non è ancora sincronizzato sul "
                    'dispositivo, quindi questo cliente non può essere '
                    'letto dalla cache locale anche se esiste sul server.',
              );
            }
            return _CustomerDetailBody(customer: customer, customerId: customerId);
          },
        ),
      ),
    );
  }
}

/// Delete confirmation dialog + API call, shared by the header trash action.
///
/// Mirrors the confirm-then-call pattern already used for destructive actions elsewhere in the
/// app (e.g. `_removeMember` in admin_squadra_detail_screen.dart): a plain `AlertDialog` via
/// `showDialog<bool>`, no shared dialog widget exists yet in this codebase to reuse.
Future<void> _deleteCustomer(BuildContext context, WidgetRef ref, String customerId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminare il cliente?'),
      content: const Text(
        'Il cliente verrà disattivato. Sedi, contratti e interventi collegati '
        'restano consultabili ma non sarà più selezionabile per nuovi lavori.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(adminApiClientProvider).deleteCustomer(customerId);
    unawaited(ref.read(syncProvider.notifier).performSync());
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cliente eliminato')));
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

class _CustomerDetailBody extends ConsumerWidget {
  const _CustomerDetailBody({required this.customer, required this.customerId});
  final dynamic customer;
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: 'Cliente',
            subtitle: customer.companyName,
            showBack: true,
            actions: [
              HeaderIconBtn(
                icon: LucideIcons.trash2,
                label: 'Elimina cliente',
                glass: true,
                onTap: () => _deleteCustomer(context, ref, customerId),
              ),
            ],
          ),
        ),
        // ── Avatar hero ──────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: AppAvatar(name: customer.companyName, size: 64),
            ),
          ),
        ),
        // ── Contatti card ──────────────────────────────────────────────────
        //
        // Contact/site fields first, fiscal fields demoted to their own labelled section below
        // (near Storico, matches the Vetro mockup's explicit call: "Contact + site first — what
        // a technician needs — fiscal data demoted to its own labeled section rather than mixed
        // in"). P.IVA used to sit second, right after the company name.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
            child: VetroCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(title: 'Contatti'),
                  const SizedBox(height: 4),
                  KeyVal(label: 'Ragione sociale', value: customer.companyName),
                  if (customer.contactPerson != null && customer.contactPerson!.isNotEmpty)
                    KeyVal(label: 'Referente', value: customer.contactPerson!),
                  if (customer.phone != null && customer.phone!.isNotEmpty)
                    KeyVal(label: 'Telefono', value: customer.phone!),
                  if (customer.email != null && customer.email!.isNotEmpty)
                    KeyVal(label: 'Email', value: customer.email!),
                  if (customer.address != null && customer.address!.isNotEmpty)
                    KeyVal(label: 'Indirizzo', value: customer.address!),
                  if (customer.city != null && customer.city!.isNotEmpty)
                    KeyVal(label: 'Città', value: customer.city!),
                  if (customer.postalCode != null && customer.postalCode!.isNotEmpty)
                    KeyVal(label: 'CAP', value: customer.postalCode!),
                  KeyVal(
                    label: 'Paese',
                    value: customer.country != null && customer.country!.isNotEmpty
                        ? customer.country!
                        : '—',
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── Panoramica (sedi/contratti/interventi) ────────────────────────
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
            child: _OverviewCard(customerId: customerId),
          ),
        ),
        // ── Sedi (Gap 3) ─────────────────────────────────────────────────
        SliverToBoxAdapter(child: _SediSection(customerId: customerId)),
        // ── Contratti (Gap 7, read-only + create) ───────────────────────
        SliverToBoxAdapter(child: _ContrattiSection(customerId: customerId)),
        // ── Prodotti assistenza (Gap 8, read-only + create) ─────────────
        SliverToBoxAdapter(child: _ProdottiSection(customerId: customerId)),
        // ── Note ─────────────────────────────────────────────────────────
        if (customer.notes != null && customer.notes!.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: VetroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(title: 'Note'),
                    const SizedBox(height: 4),
                    Text(customer.notes!, style: AppTextStyles.bodyMedium),
                  ],
                ),
              ),
            ),
          ),
        ],
        // ── Status ───────────────────────────────────────────────────────
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
            child: VetroCard(
              child: Row(
                children: [
                  Text(
                    'Stato',
                    style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkMuted),
                  ),
                  const Spacer(),
                  StatusPill(stato: customer.isActive ? 'Attivo' : 'Inattivo', outlined: true),
                ],
              ),
            ),
          ),
        ),
        // ── Dati fiscali ─────────────────────────────────────────────────
        //
        // Demoted to its own labelled, last-in-scroll section — see the Contatti card's own
        // comment. Only taxId (P.IVA) is captured locally today; SDI/PEC/Codice Fiscale appear in
        // the mockup's copy but have no column in the Customers Drift table (backend `Customer.cs`
        // may hold more than what mobile's mirror ever synced) — a real gap, out of scope for a
        // layout-only pass, not silently invented here.
        if (customer.taxId != null && customer.taxId!.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: VetroCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(title: 'Dati fiscali'),
                    const SizedBox(height: 4),
                    KeyVal(label: 'P.IVA', value: customer.taxId!, showDivider: false),
                  ],
                ),
              ),
            ),
          ),
        ],
        // ── Storico interventi ─────────────────────────────────────────────
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
            child: _TicketHistoryCard(customerId: customerId),
          ),
        ),
        SliverPadding(padding: EdgeInsets.only(bottom: context.fabSafeBottom)),
      ],
    );
  }
}

/// The aggregated overview (sedi/contratti/interventi counts) from
/// `GET /api/app/clienti/{id}/overview` — data the API client + provider already fetched, just
/// never rendered anywhere (see `clienteOverviewProvider` in clienti_providers.dart).
class _OverviewCard extends ConsumerWidget {
  const _OverviewCard({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(clienteOverviewProvider(customerId));

    return VetroCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: overviewAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Text(
          e is ClienteOverviewOfflineException
              ? 'Panoramica non disponibile offline'
              : 'Panoramica non disponibile',
          style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
        ),
        data: (overview) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(title: 'Panoramica'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _OverviewStat(label: 'Sedi attive', value: '${overview.sediAttive}'),
                ),
                Expanded(
                  child: _OverviewStat(label: 'Contratti', value: '${overview.contratti}'),
                ),
                Expanded(
                  child: _OverviewStat(
                    label: 'Interventi',
                    value: '${overview.interventiTotali}',
                  ),
                ),
                Expanded(
                  child: _OverviewStat(label: 'Aperti', value: '${overview.interventiAperti}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.colors.inkMuted),
        ),
      ],
    );
  }
}

/// The customer's ticket history from the local Drift cache — `ticketsForCustomerProvider`
/// existed with no widget consuming it.
// ══════════════════════════════════════════════════════════════════════════════
// Sedi (Gap 3) — locations are synced to Drift (unlike cantiere contacts/assignments), so the
// list itself is offline-capable via `locationsForCustomerProvider`. Create/edit/delete all go
// through the global Sedi CRUD (`admin_location_form_screen.dart` / `admin_location_detail_
// screen.dart`, both already built) rather than duplicating that form inline — "nuova" is pushed
// pre-scoped to this customer via `extra`, edit pushes straight to the edit form, delete is
// inline (mirrors `_deleteCustomer`'s confirm-then-call, no separate screen needed for that).
// ══════════════════════════════════════════════════════════════════════════════

class _SediSection extends ConsumerWidget {
  const _SediSection({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(locationsForCustomerProvider(customerId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Sedi',
          action: IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Nuova sede',
            onPressed: () => context.push('/altro/sedi/nuova', extra: customerId),
          ),
        ),
        locationsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              _SectionError(onRetry: () => ref.invalidate(locationsForCustomerProvider(customerId))),
          data: (locations) {
            if (locations.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.mapPin,
                title: 'Nessuna sede',
                body: 'Aggiungi una sede per questo cliente con il pulsante +.',
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: Column(
                children: locations.asMap().entries.map((entry) {
                  final loc = entry.value;
                  return ListRow(
                    leading: const RowIconTile(icon: LucideIcons.mapPin),
                    title: loc.name,
                    subtitle: loc.city != null && loc.city!.isNotEmpty ? loc.city : null,
                    meta: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.pencil, size: 18),
                          tooltip: 'Modifica sede',
                          onPressed: () => context.push('/altro/sedi/${loc.id}/modifica'),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, size: 18),
                          tooltip: 'Elimina sede',
                          onPressed: () => _deleteLocation(context, ref, id: loc.id, name: loc.name),
                        ),
                      ],
                    ),
                    onTap: () => context.push('/altro/sedi/${loc.id}'),
                    showDivider: entry.key < locations.length - 1,
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _deleteLocation(
    BuildContext context,
    WidgetRef ref, {
    required String id,
    required String name,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare la sede?'),
        content: Text('Vuoi eliminare "$name" dalle sedi di questo cliente?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(adminApiClientProvider).deleteLocation(id);
      unawaited(ref.read(syncProvider.notifier).performSync());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sede eliminata')));
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
}

// ══════════════════════════════════════════════════════════════════════════════
// Contratti (Gap 7) — no local Drift mirror (like the cantiere's live-fetched sub-resources), so
// this reads live via `AdminApiClient.fetchContracts(customerId: ...)`, server-side filtered.
// Read-only list is the priority per the audit; "+" reuses the existing global create form
// (`admin_contract_form_screen.dart`) rather than teaching it a pre-selected customer — cheap to
// link, not cheap to also thread a new constructor param through a form that already resolves its
// customer from a dropdown.
// ══════════════════════════════════════════════════════════════════════════════

/// Contracts for [customerId] — `GET /api/contracts?customerId=`.
final adminCustomerContractsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, customerId) async {
      final api = ref.watch(adminApiClientProvider);
      return api.fetchContracts(customerId: customerId);
    });

class _ContrattiSection extends ConsumerWidget {
  const _ContrattiSection({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contractsAsync = ref.watch(adminCustomerContractsProvider(customerId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Contratti',
          action: IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Nuovo contratto',
            onPressed: () => context.push('/altro/contratti/nuovo'),
          ),
        ),
        contractsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _SectionError(
            onRetry: () => ref.invalidate(adminCustomerContractsProvider(customerId)),
          ),
          data: (contracts) {
            if (contracts.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.fileSignature,
                title: 'Nessun contratto',
                body: 'Non risultano contratti per questo cliente.',
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: Column(
                children: contracts.asMap().entries.map((entry) {
                  final c = entry.value;
                  final name = c['name'] as String? ?? '';
                  final isActive = c['isActive'] as bool? ?? true;
                  final price = c['price'] as num?;
                  return ListRow(
                    leading: const RowIconTile(icon: LucideIcons.fileSignature),
                    title: name,
                    subtitle: price != null ? '€${price.toStringAsFixed(2)}' : null,
                    meta: isActive
                        ? null
                        : const StatusPill(stato: 'Inattivo', small: true, outlined: true),
                    onTap: () => context.push('/altro/contratti/${c['id']}', extra: c),
                    showDivider: entry.key < contracts.length - 1,
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Prodotti assistenza (Gap 8) — same treatment as Contratti: no Drift mirror, live-fetched and
// server-filtered by customerId, read-only priority with a cheap "+" to the existing global form.
// ══════════════════════════════════════════════════════════════════════════════

/// Prodotti assistenza for [customerId] — `GET /api/prodottoassistenza?customerId=`.
final adminCustomerProdottiProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, customerId) async {
      final api = ref.watch(adminApiClientProvider);
      return api.fetchProdottiAssistenza(customerId: customerId);
    });

class _ProdottiSection extends ConsumerWidget {
  const _ProdottiSection({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prodottiAsync = ref.watch(adminCustomerProdottiProvider(customerId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Prodotti assistenza',
          action: IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Nuovo prodotto',
            onPressed: () => context.push('/altro/prodotti/nuovo'),
          ),
        ),
        prodottiAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _SectionError(
            onRetry: () => ref.invalidate(adminCustomerProdottiProvider(customerId)),
          ),
          data: (prodotti) {
            if (prodotti.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.wrench,
                title: 'Nessun prodotto',
                body: 'Non risultano prodotti in assistenza per questo cliente.',
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: Column(
                children: prodotti.asMap().entries.map((entry) {
                  final p = entry.value;
                  final name = p['name'] as String? ?? '';
                  final serialNumber = p['serialNumber'] as String?;
                  final isActive = p['isActive'] as bool? ?? true;
                  return ListRow(
                    leading: const RowIconTile(icon: LucideIcons.wrench),
                    title: name,
                    subtitle: serialNumber != null && serialNumber.isNotEmpty
                        ? serialNumber
                        : null,
                    meta: isActive
                        ? null
                        : const StatusPill(stato: 'Inattivo', small: true, outlined: true),
                    onTap: () => context.push('/altro/prodotti/${p['id']}', extra: p),
                    showDivider: entry.key < prodotti.length - 1,
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared inline error for a section — mirrors `_SectionError` in
// admin_cantiere_detail_screen.dart (a failed sub-section should not block the rest of the
// detail screen from being usable).
// ══════════════════════════════════════════════════════════════════════════════

class _SectionError extends StatelessWidget {
  const _SectionError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pagePadding,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: context.colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Impossibile caricare. Riprova.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.red),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Riprova')),
        ],
      ),
    );
  }
}

class _TicketHistoryCard extends ConsumerWidget {
  const _TicketHistoryCard({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(ticketsForCustomerProvider(customerId));

    return VetroCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: ticketsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Text(
          'Storico interventi non disponibile',
          style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
        ),
        data: (tickets) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(title: 'Storico interventi', trailing: '${tickets.length}'),
            const SizedBox(height: 4),
            if (tickets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nessun intervento registrato per questo cliente.',
                  style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
                ),
              )
            else
              for (var i = 0; i < tickets.length; i++)
                ListRow(
                  title: tickets[i].title,
                  subtitle: tickets[i].numero != null ? '#${tickets[i].numero}' : '—',
                  showDivider: i < tickets.length - 1,
                  onTap: () => context.push('/ticket/${tickets[i].id}'),
                ),
          ],
        ),
      ),
    );
  }
}
