// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/error_message.dart' show isTransportOrServerFault;
import '../../../core/widgets/detail/detail_facts_grid.dart';
import '../../../core/widgets/detail/detail_hero.dart';
import '../../../core/widgets/detail/detail_link_row.dart';
import '../../../core/widgets/detail/detail_scaffold.dart';
import '../../../core/widgets/detail/detail_section.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/clienti/customer_contact_api_client.dart';
import '../../../data/local/app_database.dart' show Customer, CustomerContactRow, Location, Ticket;
import '../../../data/reference/reference_cache_repository.dart';
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/sync/sync_freshness_provider.dart';
import '../../../data/sync/sync_service.dart';
import '../../clienti/clienti_providers.dart';
import '../../ticket/ticket_detail_api_client.dart' show TicketDetailOfflineException;
import '../admin_api_client.dart';

/// Admin customer detail — the wave-0 summary shell: hero + `Modifica`, then the two things a
/// person opening a cliente needs in order (Relazioni, Sintesi, Attività, Documenti).
class AdminCustomerDetailScreen extends ConsumerWidget {
  const AdminCustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailProvider(customerId));

    return customerAsync.when(
      loading: () => const DetailScaffold.loading(screenTitle: 'Cliente'),
      error: (e, _) => DetailScaffold.unavailable(
        screenTitle: 'Cliente',
        icon: LucideIcons.alertTriangle,
        title: 'Cliente non disponibile',
        reason: 'Non è stato possibile leggere il cliente salvato su questo telefono.',
        onRetry: () => ref.invalidate(customerDetailProvider(customerId)),
      ),
      data: (customer) {
        if (customer == null) {
          final neverSynced = ref.watch(hasSyncedAtLeastOnceProvider).valueOrNull == false;
          return DetailScaffold.unavailable(
            screenTitle: 'Cliente',
            icon: neverSynced ? LucideIcons.cloudOff : LucideIcons.users,
            title: neverSynced ? 'Cliente non disponibile' : 'Cliente non trovato',
            reason: neverSynced
                ? "L'elenco clienti non è ancora sincronizzato sul dispositivo, quindi questo "
                      'cliente non può essere letto dalla cache locale anche se esiste sul server.'
                : 'Questo cliente non è più disponibile: potrebbe essere stato eliminato.',
          );
        }
        return _CustomerDetailBody(customer: customer, customerId: customerId);
      },
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

/// True when an async list should keep its section on screen: still loading, failed, or holding
/// at least one row. Only "loaded and empty" hides a section, per the prototype rule.
bool _hasSectionData<T>(AsyncValue<List<T>> value) =>
    value.isLoading || value.hasError || (value.valueOrNull?.isNotEmpty ?? false);

bool _present(String? value) => value != null && value.trim().isNotEmpty;

String? _joinMeta(List<String> parts) => parts.isEmpty ? null : parts.join(' · ');

String _countLabel(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';

class _CustomerDetailBody extends ConsumerWidget {
  const _CustomerDetailBody({required this.customer, required this.customerId});

  final Customer customer;
  final String customerId;

  /// Pull-to-refresh: sync first, then re-request the sections that are fetched live.
  ///
  /// The customer, its sedi, its ticket history and its contacts come from the synced mirror, which
  /// [refreshWithFeedback] already covers. The overview, contracts and prodotti have no Drift copy —
  /// they are autoDispose providers that call the API once and then sit on that answer — so a sync
  /// alone leaves them exactly as stale as they were, and invalidating them is the only thing that
  /// makes the pull mean something for those three sections.
  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    await refreshWithFeedback(context, ref);
    if (!context.mounted) return;
    ref.invalidate(clienteOverviewProvider(customerId));
    ref.invalidate(adminCustomerContractsProvider(customerId));
    ref.invalidate(adminCustomerProdottiProvider(customerId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(clienteOverviewProvider(customerId));
    final locationsAsync = ref.watch(locationsForCustomerProvider(customerId));
    final contactsAsync = ref.watch(customerContactsProvider(customerId));
    final contractsAsync = ref.watch(adminCustomerContractsProvider(customerId));
    final prodottiAsync = ref.watch(adminCustomerProdottiProvider(customerId));
    final ticketsAsync = ref.watch(ticketsForCustomerProvider(customerId));
    final online = ref.watch(isOnlineProvider);

    final overview = overviewAsync.valueOrNull;
    final locations = locationsAsync.valueOrNull;
    final contacts = contactsAsync.valueOrNull;
    final contracts = contractsAsync.valueOrNull;
    final sediCount = overview?.sediAttive ?? locations?.length;
    final contrattiCount = overview?.contratti ?? contracts?.length;

    final sintesiFacts = _sintesiFacts(customer);
    final hasNotes = _present(customer.notes);
    final relazioniEmpty =
        !_hasSectionData(locationsAsync) &&
        !_hasSectionData(contactsAsync) &&
        !_hasSectionData(prodottiAsync);
    final attivitaEmpty = !_hasSectionData(ticketsAsync);
    final documentiEmpty = !_hasSectionData(contractsAsync);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below 360 the 9px mono section meta cannot share the row with a 17px section title: the
        // trailing text becomes the only thing on screen and pushes the title out. Drop the meta
        // there and let each Relazioni group header carry its own count instead.
        final narrowHeader = constraints.maxWidth < 360;

        return DetailScaffold(
          screenTitle: 'Cliente',
          headerActions: [
            HeaderIconBtn(
              icon: LucideIcons.trash2,
              label: 'Elimina cliente',
              glass: true,
              onTap: () => _deleteCustomer(context, ref, customerId),
            ),
            PopupMenuButton<_CustomerAction>(
              tooltip: 'Aggiungi',
              icon: const Icon(LucideIcons.moreHorizontal),
              onSelected: (action) => _handleAction(context, ref, action, online: online),
              itemBuilder: (context) => [
                const PopupMenuItem(value: _CustomerAction.nuovaSede, child: Text('Nuova sede')),
                if (online)
                  const PopupMenuItem(
                    value: _CustomerAction.nuovoReferente,
                    child: Text('Aggiungi referente'),
                  ),
                const PopupMenuItem(value: _CustomerAction.nuovoAsset, child: Text('Nuovo asset')),
                const PopupMenuItem(
                  value: _CustomerAction.nuovoContratto,
                  child: Text('Nuovo contratto'),
                ),
              ],
            ),
          ],
          hero: DetailHeroData(
            variant: DetailHeroVariant.summary,
            kind: 'Summary · cliente',
            kicker: 'Summary',
            kickerContext: 'cliente',
            title: customer.companyName.trim().isEmpty ? 'Cliente' : customer.companyName,
            subtitle: _heroFacts(customer, sediCount: sediCount, contrattiCount: contrattiCount),
            status: DetailStatus(label: customer.isActive ? 'Attivo' : 'Inattivo'),
            primaryAction: DetailAction(
              label: 'Modifica',
              onPressed: () async {
                await context.push<bool>('/altro/clienti/$customerId/modifica');
              },
            ),
          ),
          sections: [
            DetailSectionData(
              title: 'Relazioni',
              isEmpty: relazioniEmpty,
              trailing: narrowHeader
                  ? null
                  : _relationMeta(
                      sedi: sediCount,
                      contratti: contrattiCount,
                      referenti: contacts?.length,
                    ),
              child: _relationsContent(
                context,
                ref,
                locationsAsync: locationsAsync,
                contactsAsync: contactsAsync,
                prodottiAsync: prodottiAsync,
                online: online,
              ),
            ),
            DetailSectionData(
              title: 'Sintesi',
              isEmpty: sintesiFacts.isEmpty && !hasNotes,
              trailing: narrowHeader ? null : const DetailSectionMeta('Anagrafica e dati fiscali'),
              child: _sintesiContent(customer, facts: sintesiFacts, hasNotes: hasNotes),
            ),
            DetailSectionData(
              title: 'Attività',
              isEmpty: attivitaEmpty,
              trailing: narrowHeader ? null : const DetailSectionMeta('Ultimi interventi'),
              child: _attivitaContent(context, ref, ticketsAsync),
            ),
            DetailSectionData(
              title: 'Documenti',
              isEmpty: documentiEmpty,
              trailing: narrowHeader ? null : const DetailSectionMeta('Contratti'),
              child: _documentiContent(context, ref, contractsAsync),
            ),
          ],
          onRefresh: () => _refresh(context, ref),
        );
      },
    );
  }

  // ── Header actions ──────────────────────────────────────────────────────────

  void _handleAction(
    BuildContext context,
    WidgetRef ref,
    _CustomerAction action, {
    required bool online,
  }) {
    switch (action) {
      case _CustomerAction.nuovaSede:
        context.push('/altro/sedi/nuova', extra: customerId);
      case _CustomerAction.nuovoReferente:
        if (online) {
          _openContactSheet(context, ref, customerId: customerId, contact: null);
        }
      case _CustomerAction.nuovoAsset:
        context.push('/altro/prodotti/nuovo');
      case _CustomerAction.nuovoContratto:
        context.push('/altro/contratti/nuovo');
    }
  }

  // ── Relazioni ───────────────────────────────────────────────────────────────

  Widget? _relationMeta({int? sedi, int? contratti, int? referenti}) {
    final parts = <String>[
      if (sedi != null) _countLabel(sedi, 'sede', 'sedi'),
      if (contratti != null) _countLabel(contratti, 'contratto', 'contratti'),
      if (referenti != null) _countLabel(referenti, 'referente', 'referenti'),
    ];
    return parts.isEmpty ? null : DetailSectionMeta(parts.join(' · '));
  }

  Widget _relationsContent(
    BuildContext context,
    WidgetRef ref, {
    required AsyncValue<List<Location>> locationsAsync,
    required AsyncValue<List<CustomerContactRow>> contactsAsync,
    required AsyncValue<List<Map<String, dynamic>>> prodottiAsync,
    required bool online,
  }) {
    final blocks = <Widget>[];

    void addGroup(String label, int? count, Widget content, {bool visible = true}) {
      if (!visible) return;
      blocks.add(_RelationGroupHeader(label: count == null ? label : '$label · $count'));
      blocks.add(content);
    }

    addGroup(
      'Sedi',
      locationsAsync.valueOrNull?.length,
      _locationsContent(context, ref, locationsAsync),
      visible: _hasSectionData(locationsAsync),
    );
    addGroup(
      'Referenti',
      contactsAsync.valueOrNull?.length,
      _contactsContent(context, ref, contactsAsync, online: online),
      visible: _hasSectionData(contactsAsync),
    );
    addGroup(
      'Asset',
      prodottiAsync.valueOrNull?.length,
      _prodottiContent(context, ref, prodottiAsync),
      visible: _hasSectionData(prodottiAsync),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          blocks[i],
        ],
      ],
    );
  }

  Widget _locationsContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Location>> locationsAsync,
  ) {
    return locationsAsync.when(
      loading: () => const _SectionLoading(),
      error: (e, _) =>
          AppSectionError(onRetry: () => ref.invalidate(locationsForCustomerProvider(customerId))),
      data: (locations) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < locations.length; i++)
            DetailLinkRow(
              key: ValueKey('cliente-sede-${locations[i].id}'),
              title: locations[i].name,
              showDivider: i < locations.length - 1,
              trailing: _RowActions(
                meta: locations[i].city,
                editTooltip: 'Modifica sede',
                deleteTooltip: 'Elimina sede',
                onEdit: () => context.push('/altro/sedi/${locations[i].id}/modifica'),
                onDelete: () =>
                    _deleteLocation(context, ref, id: locations[i].id, name: locations[i].name),
              ),
              onTap: () => context.push('/altro/sedi/${locations[i].id}'),
            ),
        ],
      ),
    );
  }

  Widget _contactsContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<CustomerContactRow>> contactsAsync, {
    required bool online,
  }) {
    return contactsAsync.when(
      loading: () => const _SectionLoading(),
      // A Drift read has nothing to fail with short of a corrupt database, so this is a plain
      // section error rather than the offline/none split the network read used to need.
      error: (e, _) =>
          AppSectionError(onRetry: () => ref.invalidate(customerContactsProvider(customerId))),
      data: (contacts) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < contacts.length; i++)
            DetailLinkRow(
              key: ValueKey('cliente-referente-${contacts[i].id}'),
              title: contacts[i].name.isNotEmpty ? contacts[i].name : 'Referente',
              showDivider: i < contacts.length - 1,
              trailing: _RowActions(
                meta: _joinMeta([
                  if (_present(contacts[i].role)) contacts[i].role!,
                  if (_present(contacts[i].phone)) contacts[i].phone!,
                ]),
                editTooltip: 'Modifica referente',
                deleteTooltip: 'Elimina referente',
                // Edit and delete are POST/PUT/DELETE with no queue behind them, so offline the
                // affordance is hidden rather than left to fail. The rows themselves stay.
                onEdit: online
                    ? () => _openContactSheet(
                        context,
                        ref,
                        customerId: customerId,
                        contact: contacts[i],
                      )
                    : null,
                onDelete: online
                    ? () => _deleteContact(
                        context,
                        ref,
                        customerId: customerId,
                        contactId: contacts[i].id,
                        name: contacts[i].name,
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _prodottiContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Map<String, dynamic>>> prodottiAsync,
  ) {
    return prodottiAsync.when(
      loading: () => const _SectionLoading(),
      error: (e, _) => e is TicketDetailOfflineException
          ? const _SectionNote(
              'Asset non disponibili offline: apri questa scheda con una connessione per '
              'scaricarli.',
            )
          : AppSectionError(
              onRetry: () => ref.invalidate(adminCustomerProdottiProvider(customerId)),
            ),
      data: (prodotti) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < prodotti.length; i++)
            DetailLinkRow(
              key: ValueKey('cliente-asset-${prodotti[i]['id']}'),
              title: prodotti[i]['name'] as String? ?? 'Asset',
              meta: _present(prodotti[i]['serialNumber'] as String?)
                  ? prodotti[i]['serialNumber'] as String?
                  : (prodotti[i]['categoria'] as String?),
              showDivider: i < prodotti.length - 1,
              onTap: () => context.push('/altro/prodotti/${prodotti[i]['id']}', extra: prodotti[i]),
            ),
        ],
      ),
    );
  }

  // ── Sintesi ─────────────────────────────────────────────────────────────────

  List<DetailFact> _sintesiFacts(Customer c) {
    // Città lives in the hero facts line on purpose: the prototype puts it there and the rule is
    // "no fact repeated between hero and Sintesi". Every other anagrafica/fiscal field is here.
    return [
      if (_present(c.address)) DetailFact(label: 'Indirizzo', value: c.address!),
      if (_present(c.postalCode)) DetailFact(label: 'CAP', value: c.postalCode!),
      if (_present(c.province)) DetailFact(label: 'Provincia', value: c.province!),
      if (_present(c.country)) DetailFact(label: 'Paese', value: c.country!),
      if (_present(c.phone)) DetailFact(label: 'Telefono', value: c.phone!),
      if (_present(c.cellulare)) DetailFact(label: 'Cellulare', value: c.cellulare!),
      if (_present(c.email)) DetailFact(label: 'Email', value: c.email!),
      if (_present(c.contactPerson)) DetailFact(label: 'Referente', value: c.contactPerson!),
      if (_present(c.taxId)) DetailFact(label: 'P.IVA', value: c.taxId!),
      if (_present(c.fiscalCode)) DetailFact(label: 'Codice fiscale', value: c.fiscalCode!),
      if (_present(c.sdiCode)) DetailFact(label: 'Codice SDI', value: c.sdiCode!),
      if (_present(c.pec)) DetailFact(label: 'PEC', value: c.pec!),
    ];
  }

  Widget _sintesiContent(Customer c, {required List<DetailFact> facts, required bool hasNotes}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (facts.isNotEmpty) DetailFactsGrid(facts: facts),
        if (facts.isNotEmpty && hasNotes) const SizedBox(height: AppSpacing.md),
        if (hasNotes) _NoteBlock(note: c.notes!),
      ],
    );
  }

  // ── Attività ────────────────────────────────────────────────────────────────

  Widget _attivitaContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Ticket>> ticketsAsync,
  ) {
    return ticketsAsync.when(
      loading: () => const _SectionLoading(),
      error: (e, _) => const _SectionNote('Storico interventi non disponibile.'),
      data: (tickets) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tickets.length; i++)
            DetailLinkRow(
              key: ValueKey('cliente-intervento-${tickets[i].id}'),
              title: tickets[i].title,
              meta: tickets[i].numero != null ? '#${tickets[i].numero}' : null,
              showDivider: i < tickets.length - 1,
              onTap: () => context.push('/ticket/${tickets[i].id}'),
            ),
        ],
      ),
    );
  }

  // ── Documenti ───────────────────────────────────────────────────────────────

  Widget _documentiContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Map<String, dynamic>>> contractsAsync,
  ) {
    return contractsAsync.when(
      loading: () => const _SectionLoading(),
      error: (e, _) => e is TicketDetailOfflineException
          ? const _SectionNote(
              'Contratti non disponibili offline: apri questa scheda con una connessione per '
              'scaricarli.',
            )
          : AppSectionError(
              onRetry: () => ref.invalidate(adminCustomerContractsProvider(customerId)),
            ),
      data: (contracts) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < contracts.length; i++)
            DetailLinkRow(
              key: ValueKey('cliente-contratto-${contracts[i]['id']}'),
              title: contracts[i]['name'] as String? ?? 'Contratto',
              showDivider: i < contracts.length - 1,
              trailing: StatusStamp(
                stato: (contracts[i]['isActive'] as bool? ?? true) ? 'Attivo' : 'Inattivo',
                size: StampSize.small,
              ),
              semanticsLabel:
                  '${contracts[i]['name'] as String? ?? 'Contratto'}. '
                  '${(contracts[i]['isActive'] as bool? ?? true) ? 'Attivo' : 'Inattivo'}',
              onTap: () =>
                  context.push('/altro/contratti/${contracts[i]['id']}', extra: contracts[i]),
            ),
        ],
      ),
    );
  }

  // ── Contact sheet + writes ──────────────────────────────────────────────────

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
      await _pullAfterWrite(ref);
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
    required CustomerContactRow? contact,
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
        onSaved: () => _pullAfterWrite(ref),
      ),
    );
  }

  /// A contact write landed on the server. The list reads the Drift mirror, so the sync is what
  /// puts the change on screen — the sheet has already closed and toasted by then, and
  /// `performSync` never throws (it parks the outcome in `SyncState`), so a refresh that fails
  /// leaves the previous list rather than contradicting the success the user was shown.
  Future<void> _pullAfterWrite(WidgetRef ref) => ref.read(syncProvider.notifier).performSync();
}

/// The hero's muted facts line: city first, then the two counts the prototype puts in the hero —
/// never the same facts again in Sintesi.
String? _heroFacts(Customer customer, {int? sediCount, int? contrattiCount}) {
  final parts = <String>[
    if (_present(customer.city)) customer.city!.trim(),
    if (sediCount != null) _countLabel(sediCount, 'sede', 'sedi'),
    if (contrattiCount != null) _countLabel(contrattiCount, 'contratto', 'contratti'),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// A mono group label inside Relazioni — `SEDI`, `REFERENTI`, `ASSET`.
class _RelationGroupHeader extends StatelessWidget {
  const _RelationGroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: AppTextStyles.docCode.copyWith(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.54,
        color: context.colors.inkMuted,
      ),
    );
  }
}

enum _CustomerAction { nuovaSede, nuovoReferente, nuovoAsset, nuovoContratto }

/// The trailing side of a relation row: an optional mono meta line plus the entity's own actions.
///
/// `DetailLinkRow` replaces its own meta with `trailing`, so the row has to draw the meta here.
/// Icons keep a 44px target without changing the drawn size.
class _RowActions extends StatelessWidget {
  const _RowActions({this.meta, this.editTooltip, this.deleteTooltip, this.onEdit, this.onDelete});

  final String? meta;
  final String? editTooltip;
  final String? deleteTooltip;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final hasMeta = _present(meta);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasMeta)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              meta!.toUpperCase(),
              maxLines: 1,
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
        if (onEdit != null)
          _ActionIcon(
            icon: LucideIcons.pencil,
            tooltip: editTooltip ?? 'Modifica',
            onPressed: onEdit!,
          ),
        if (onDelete != null)
          _ActionIcon(
            icon: LucideIcons.trash2,
            tooltip: deleteTooltip ?? 'Elimina',
            onPressed: onDelete!,
          ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Static, non-spinning placeholder for a section that is still resolving, so a slow mirror does
/// not make the page jump or spin.
class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    final rule = context.colors.borderLight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 2; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: i == 0 ? 0.55 : 0.35,
              child: Container(
                height: 10,
                decoration: BoxDecoration(color: rule, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
      ],
    );
  }
}

/// A muted one-line state inside a section (offline or unavailable), styled like the shell's meta.
class _SectionNote extends StatelessWidget {
  const _SectionNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        message,
        style: AppTextStyles.bodySmall.copyWith(
          fontSize: 11,
          height: 1.4,
          color: context.colors.inkMuted,
        ),
      ),
    );
  }
}

class _NoteBlock extends StatelessWidget {
  const _NoteBlock({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NOTE',
          style: AppTextStyles.docCode.copyWith(
            fontSize: 8,
            letterSpacing: 0.64,
            color: context.colors.inkMuted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          note,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: 11.5,
            height: 1.4,
            color: context.colors.ink,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Contratti (Gap 7) — server-first via `AdminApiClient.fetchContracts(customerId: ...)`, with the
// synced `contracts` mirror as the offline answer (the same rows the Contratti list uses).
// Read-only list is the priority per the audit; "+" reuses the existing global create form.
// ══════════════════════════════════════════════════════════════════════════════

/// Contracts for [customerId] — `GET /api/contracts?customerId=`, mirror on the way back.
///
/// Inactive contracts are included, because the server returns them too (they carry an "Inattivo"
/// stamp). The mirror has no price column, so a mirrored row's subtitle stays empty rather than
/// printing a made-up €0,00.
final adminCustomerContractsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, customerId) async {
      Future<List<Map<String, dynamic>>> fromMirror() async {
        final rows = await ref
            .watch(referenceCacheProvider)
            .contractsForCustomer(customerId, activeOnly: false);
        if (rows.isEmpty && await ref.watch(appDatabaseProvider).getLastSync() == null) {
          throw const TicketDetailOfflineException();
        }
        return [
          for (final c in rows)
            {
              'id': c.id,
              'name': c.name,
              'customerId': c.customerId,
              'locationId': c.locationId,
              'isActive': c.isActive,
              'numero': c.numero,
              'codice': c.codice,
              'externalId': c.externalId,
            },
        ];
      }

      if (ref.watch(isOnlineProvider)) {
        try {
          return await ref.watch(adminApiClientProvider).fetchContracts(customerId: customerId);
        } catch (e) {
          if (!isTransportOrServerFault(e)) rethrow;
        }
      }
      return fromMirror();
    });

// ══════════════════════════════════════════════════════════════════════════════
// Prodotti assistenza (Gap 8) — same treatment as Contratti: server-first,
// customer-filtered, with the synced `prodotti_assistenza` mirror behind it.
// ══════════════════════════════════════════════════════════════════════════════

/// Prodotti assistenza for [customerId] — `GET /api/prodottoassistenza?customerId=`, mirror on
/// the way back. Inactive assets included, same reasoning as
/// [adminCustomerContractsProvider]; `customerName` is omitted because the section already knows
/// whose assets these are.
final adminCustomerProdottiProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, customerId) async {
      Future<List<Map<String, dynamic>>> fromMirror() async {
        final rows = await ref
            .watch(referenceCacheProvider)
            .prodottiForCustomer(customerId, activeOnly: false);
        if (rows.isEmpty && await ref.watch(appDatabaseProvider).getLastSync() == null) {
          throw const TicketDetailOfflineException();
        }
        return [
          for (final p in rows)
            {
              'id': p.id,
              'name': p.name,
              'codice': p.codice,
              'customerId': p.customerId,
              'locationId': p.locationId,
              'categoria': p.categoria,
              'marchio': p.marchio,
              'serialNumber': p.serialNumber,
              'externalId': p.externalId,
              'isActive': p.isActive,
            },
        ];
      }

      if (ref.watch(isOnlineProvider)) {
        try {
          return await ref
              .watch(adminApiClientProvider)
              .fetchProdottiAssistenza(customerId: customerId);
        } catch (e) {
          if (!isTransportOrServerFault(e)) rethrow;
        }
      }
      return fromMirror();
    });

// ══════════════════════════════════════════════════════════════════════════════
// Referenti (CustomerContact — a customer can now have several labeled contacts) — distinct from
// the single flat `contactPerson` string on the customer record itself. Read from the Drift mirror
// via `customerContactsProvider`; writes still go to `CustomerContactApiClient` because the
// office owns these rows, and a successful write is followed by a sync so the mirror catches up.
// Add/edit/delete all happen inline through a bottom sheet, mirroring the cantiere's own contacts
// section.
// ══════════════════════════════════════════════════════════════════════════════

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

  /// Null when adding; the existing mirror row when editing.
  final CustomerContactRow? contact;
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
