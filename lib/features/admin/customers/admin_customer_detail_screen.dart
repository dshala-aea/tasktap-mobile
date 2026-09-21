// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/clienti/cliente_overview_api_client.dart';
import '../../../data/clienti/customer_contact_api_client.dart';
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

/// Delete confirmation dialog + API call, shared by the header trash action — dialog itself is
/// the shared `confirmDeleteDialog`.
Future<void> _deleteCustomer(BuildContext context, WidgetRef ref, String customerId) async {
  final confirmed = await confirmDeleteDialog(
    context,
    title: 'Eliminare il cliente?',
    message:
        'Il cliente verrà disattivato. Sedi, contratti e interventi collegati '
        'restano consultabili ma non sarà più selezionabile per nuovi lavori.',
  );
  if (!confirmed || !context.mounted) return;

  try {
    await ref.read(adminApiClientProvider).deleteCustomer(customerId);
    unawaited(ref.read(syncProvider.notifier).performSync());
    if (context.mounted) {
      showAppToast(context, message: 'Cliente eliminato', tone: ToastTone.success);
      context.pop(true);
    }
  } catch (e) {
    if (context.mounted) {
      showAppToast(context, message: 'Impossibile eliminare. Riprova.', tone: ToastTone.error);
    }
  }
}

class _CustomerDetailBody extends ConsumerWidget {
  const _CustomerDetailBody({required this.customer, required this.customerId});
  final dynamic customer;
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: CustomScrollView(
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
                child: AppCard(
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
            // ── Referenti (labeled CustomerContact list) ────────────────────
            SliverToBoxAdapter(child: _ContactsSection(customerId: customerId)),
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
                  child: AppCard(
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
                child: AppCard(
                  child: Row(
                    children: [
                      Text(
                        'Stato',
                        style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkMuted),
                      ),
                      const Spacer(),
                      StatusPill(stato: customer.isActive ? 'Attivo' : 'Inattivo'),
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
                  child: AppCard(
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
        ),
      ),
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

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: overviewAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Text(
          e is ClienteOverviewOfflineException
              ? 'Panoramica non disponibile offline'
              : 'Panoramica non disponibile',
          style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
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
                  child: _OverviewStat(label: 'Interventi', value: '${overview.interventiTotali}'),
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
        Text(value, style: AppTextStyles.headlineMedium.copyWith(color: context.colors.ink)),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(color: context.colors.inkMuted),
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
          error: (e, _) => AppSectionError(
            onRetry: () => ref.invalidate(locationsForCustomerProvider(customerId)),
          ),
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
                          onPressed: () =>
                              _deleteLocation(context, ref, id: loc.id, name: loc.name),
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
    final confirmed = await confirmDeleteDialog(
      context,
      title: 'Eliminare la sede?',
      message: 'Vuoi eliminare "$name" dalle sedi di questo cliente?',
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(adminApiClientProvider).deleteLocation(id);
      unawaited(ref.read(syncProvider.notifier).performSync());
      if (context.mounted) {
        showAppToast(context, message: 'Sede eliminata', tone: ToastTone.success);
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, message: 'Impossibile eliminare. Riprova.', tone: ToastTone.error);
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
          error: (e, _) => AppSectionError(
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
                    meta: isActive ? null : const StatusPill(stato: 'Inattivo', small: true),
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
          error: (e, _) => AppSectionError(
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
                    subtitle: serialNumber != null && serialNumber.isNotEmpty ? serialNumber : null,
                    meta: isActive ? null : const StatusPill(stato: 'Inattivo', small: true),
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

class _TicketHistoryCard extends ConsumerWidget {
  const _TicketHistoryCard({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsAsync = ref.watch(ticketsForCustomerProvider(customerId));

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: ticketsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Text(
          'Storico interventi non disponibile',
          style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
        ),
        data: (tickets) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(title: 'Storico interventi', trailing: '${tickets.length}'),
            const SizedBox(height: 4),
            if (tickets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  'Nessun intervento registrato per questo cliente.',
                  style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
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

// ══════════════════════════════════════════════════════════════════════════════
// Referenti (CustomerContact — a customer can now have several labeled contacts) — distinct from
// the single flat `contactPerson` string on the customer record itself
// (admin_customer_form_screen.dart's own `_contactPersonCtrl`, deliberately left untouched: this
// is a new, separate concept added alongside it, not a replacement). No Drift mirror, live-fetched
// via `customerContactsProvider` / `CustomerContactApiClient`. Add/edit/delete all happen inline
// through a bottom sheet, mirroring the cantiere's own contacts section
// (`_ContactsSection`/`_ContactFormSheet` in admin_cantiere_detail_screen.dart) — the closest
// existing pattern in this app for a labeled sub-entity list with the same
// name/role/phone/email/notes shape.
// ══════════════════════════════════════════════════════════════════════════════

class _ContactsSection extends ConsumerWidget {
  const _ContactsSection({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(customerContactsProvider(customerId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Referenti',
          action: IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Aggiungi referente',
            onPressed: () => _openContactSheet(context, ref, customerId: customerId, contact: null),
          ),
        ),
        contactsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              AppSectionError(onRetry: () => ref.invalidate(customerContactsProvider(customerId))),
          data: (contacts) {
            if (contacts.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.users,
                title: 'Nessun referente',
                body: 'Aggiungi un referente per questo cliente con il pulsante +.',
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: Column(
                children: contacts.asMap().entries.map((entry) {
                  final c = entry.value;
                  final subtitleParts = [
                    if (c.role != null && c.role!.isNotEmpty) c.role!,
                    if (c.phone != null && c.phone!.isNotEmpty) c.phone!,
                  ];
                  return ListRow(
                    leading: const RowIconTile(icon: LucideIcons.user),
                    title: c.name.isNotEmpty ? c.name : 'Referente',
                    subtitle: subtitleParts.isNotEmpty ? subtitleParts.join(' · ') : null,
                    meta: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(LucideIcons.pencil, size: 18),
                          tooltip: 'Modifica referente',
                          onPressed: () =>
                              _openContactSheet(context, ref, customerId: customerId, contact: c),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, size: 18),
                          tooltip: 'Elimina referente',
                          onPressed: () => _deleteContact(
                            context,
                            ref,
                            customerId: customerId,
                            contactId: c.id,
                            name: c.name,
                          ),
                        ),
                      ],
                    ),
                    showDivider: entry.key < contacts.length - 1,
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _deleteContact(
    BuildContext context,
    WidgetRef ref, {
    required String customerId,
    required String contactId,
    required String name,
  }) async {
    final confirmed = await confirmDeleteDialog(
      context,
      title: 'Eliminare il referente?',
      message: 'Vuoi eliminare "$name" dai referenti di questo cliente?',
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(customerContactApiClientProvider).delete(customerId, contactId);
      ref.invalidate(customerContactsProvider(customerId));
      if (context.mounted) {
        showAppToast(context, message: 'Referente eliminato', tone: ToastTone.success);
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, message: 'Impossibile eliminare. Riprova.', tone: ToastTone.error);
      }
    }
  }

  void _openContactSheet(
    BuildContext context,
    WidgetRef ref, {
    required String customerId,
    required CustomerContact? contact,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ContactFormSheet(
        customerId: customerId,
        contact: contact,
        api: ref.read(customerContactApiClientProvider),
        onSaved: () => ref.invalidate(customerContactsProvider(customerId)),
      ),
    );
  }
}

/// Bottom sheet to add or edit a customer contact — mirrors `UpsertCustomerContactRequest` (name
/// required, role/phone/email/notes optional), same shape and treatment as the cantiere's own
/// `_ContactFormSheet` in admin_cantiere_detail_screen.dart.
class _ContactFormSheet extends StatefulWidget {
  const _ContactFormSheet({
    required this.customerId,
    required this.contact,
    required this.api,
    required this.onSaved,
  });

  final String customerId;

  /// Null when adding; the existing contact when editing.
  final CustomerContact? contact;
  final CustomerContactApiClient api;
  final VoidCallback onSaved;

  @override
  State<_ContactFormSheet> createState() => _ContactFormSheetState();
}

class _ContactFormSheetState extends State<_ContactFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.contact?.name);
  late final _roleCtrl = TextEditingController(text: widget.contact?.role);
  late final _phoneCtrl = TextEditingController(text: widget.contact?.phone);
  late final _emailCtrl = TextEditingController(text: widget.contact?.email);
  late final _notesCtrl = TextEditingController(text: widget.contact?.notes);
  bool _isSaving = false;

  bool get _isEditing => widget.contact != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final name = _nameCtrl.text.trim();
      if (_isEditing) {
        await widget.api.update(
          widget.customerId,
          widget.contact!.id,
          name: name,
          role: _roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      } else {
        await widget.api.create(
          widget.customerId,
          name: name,
          role: _roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      }
      widget.onSaved();
      if (mounted) {
        showAppToast(
          context,
          message: _isEditing ? 'Referente aggiornato' : 'Referente aggiunto',
          tone: ToastTone.success,
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Impossibile salvare. Riprova.', tone: ToastTone.error);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        // + viewPadding.bottom: the keyboard-inset term alone leaves the button flush against
        // the home indicator/gesture bar once the keyboard is closed — see the cantiere sheet's
        // own identical comment.
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom +
            AppSpacing.pagePadding,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: SheetHandle(),
              ),
              Text(
                _isEditing ? 'Modifica referente' : 'Aggiungi referente',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Nome *',
                controller: _nameCtrl,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obbligatorio' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(label: 'Ruolo', controller: _roleCtrl),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Telefono',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Email',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              AppTextField(label: 'Note', controller: _notesCtrl, maxLines: 3),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: _isSaving ? 'Salvataggio…' : 'Salva',
                  onPressed: _isSaving ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
