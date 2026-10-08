// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/offline_guard.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/lookup_field.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../../admin/admin_api_client.dart';
import '../new_ticket_form_state.dart';
import '../reference_picker.dart';
import '../reference_providers.dart';
import 'blamed_field_notice.dart';
import 'read_only_caption.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 1 — Cliente + Sede
//
// Select a customer from the Drift cache, then a location (cascading filter).
// ══════════════════════════════════════════════════════════════════════════════

class StepClienteSede extends ConsumerStatefulWidget {
  const StepClienteSede({
    super.key,
    required this.state,
    required this.onChanged,
    this.blamedField,
    this.contractEditable = true,
    this.commessaClearable = true,
  });

  final NewTicketFormState state;
  final ValueChanged<NewTicketFormState> onChanged;

  /// The request field the server refused, when this wizard is a repair — see
  /// [BlamedFieldNotice]. Names one of the four references this step owns, or null.
  final String? blamedField;

  /// Whether the Contratto field is a control. `false` in edit mode, where the PUT behind this
  /// screen carries no `ContractId` at all (`TicketsController.UpdateTicketRequest`), so a pick here
  /// would be dropped by the save without a word — "Ticket aggiornato" over a contract that never
  /// moved. The field is still drawn, showing the record's real contract, with
  /// [ReadOnlyFieldCaption] under it saying why it is not editable. Defaults to `true`: the create
  /// wizard's own contract pick is real and must stay live.
  final bool contractEditable;

  /// Whether clearing the Commessa is offered. `false` in edit mode: the server applies a commessa
  /// set-only (`TicketCommandService.ApplyFields`: `if (request.CommessaId.HasValue)`), so a null
  /// sent from here is a removal the record never gets. *Picking* a commessa is real and does
  /// persist, so the field stays enabled either way — only the release is refused, with a toast
  /// rather than silence. Defaults to `true` for the create wizard.
  final bool commessaClearable;

  @override
  ConsumerState<StepClienteSede> createState() => _StepClienteSedeState();
}

class _StepClienteSedeState extends ConsumerState<StepClienteSede> {
  // Debounces the "create a new sede" call (item 11 of the admin-form audit) so a genuinely new
  // address is only persisted once the technician pauses typing, not on every keystroke —
  // onFreeText fires per character, and calling POST /api/locations that often would spam the
  // backend with an id-per-keystroke and (with a slow connection) resolve them out of order.
  Timer? _createLocationDebounce;
  bool _creatingLocation = false;
  // The name the just-created sede was saved under (same string typed into the field — see
  // _createNewLocation). Passed as the Sede field's initialText: the rekey below (locationId
  // changes from null to the new id) forces a fresh AppLookupField instance whose _initialLabel()
  // otherwise finds nothing — allLocationsProvider's local Drift mirror doesn't have the new row
  // until the sync above actually lands — and would show blank text despite a real selection.
  String? _pendingSedeName;

  /// Bumped whenever the state behind the Contratto field changes *on purpose*, so the field is
  /// rebuilt from it. The key does not carry the id it shows: `ReferencePickerField` reports a pick
  /// released by editing the text as a null selection too, so a key built from the value cannot tell
  /// a commit from a keystroke — and the create wizard turns that release into a cleared id, which
  /// would then rebuild the field under the technician mid-word and wipe what they had just typed.
  /// See the key's own comment in [_buildReferences]; the epoch moves on the commits only.
  ///
  /// The same re-key-to-reset trick as `_prodottoPickerEpoch` in `step_dettagli_ticket.dart`, for
  /// the same reason: the field has to be rebuilt from the store because it cannot be told to
  /// reload itself.
  int _contractPickerEpoch = 0;

  /// As [_contractPickerEpoch], for the Commessa field — and it covers one gesture that field alone
  /// has. A refused clear deliberately changes no state, so nothing here would rebuild the field and
  /// the box would sit empty over the commessa the record still holds; the epoch is the only thing
  /// left that can put the stored commessa back (see `onCleared` in [_buildReferences]).
  int _commessaPickerEpoch = 0;

  @override
  void dispose() {
    _createLocationDebounce?.cancel();
    super.dispose();
  }

  /// Creates a real Location for the given client from typed free text and selects it —
  /// previously onFreeText only cleared the field on empty text and silently did nothing for a
  /// genuinely new address, leaving the step permanently unable to validate (NewTicketFormState.
  /// isValid requires a resolved locationId, there is no free-text fallback for Sede).
  Future<void> _createNewLocation(String customerId, String name) async {
    if (!mounted) return;
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _creatingLocation = true);
    final String id;
    try {
      id = await ref
          .read(adminApiClientProvider)
          .createLocation(customerId: customerId, name: name);
    } catch (e) {
      // The one failure worth surfacing here: the sede was never actually persisted.
      if (mounted) {
        showAppToast(
          context,
          message: 'Impossibile creare la nuova sede. Riprova.',
          tone: ToastTone.error,
        );
        setState(() => _creatingLocation = false);
      }
      return;
    }

    // Best-effort, not allowed to fail the create above: pulls the new sede down immediately so
    // the lookup field's own cache (allLocationsProvider, sourced from the local Drift mirror) can
    // resolve its name right away — same "sync right after a write" convention
    // admin_cantiere_form_screen._save() uses, just awaited (rather than fire-and-forget) so the
    // rekey below has a real name to show instead of flashing blank until the next ordinary sync.
    // If this fails (offline blip, slow connection) the sede still exists server-side regardless —
    // selecting it below is correct either way, and an ordinary sync will pick the name up later.
    try {
      await ref.read(syncProvider.notifier).performSync();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _pendingSedeName = name;
      _creatingLocation = false;
    });
    widget.onChanged(widget.state.copyWith(locationId: id));
  }

  /// Contratto and Commessa, both scoped to the selected customer — the same scope the mirror and
  /// the search enforce (`ReferenceSearchClient.searchContracts` sends `customerId` on every
  /// query). Before a customer is chosen there is nothing to scope either to, so neither field is
  /// drawn: an empty picker with no customer reads as a broken field, not as "pick a customer
  /// first" — which is what the Sede field's own hint already says in words.
  Widget _buildReferences() {
    final customerId = widget.state.customerId;
    if (customerId == null) return const SizedBox.shrink();
    final search = ref.read(referenceSearchClientProvider);
    final contracts = ref.watch(localContractsProvider(customerId)).valueOrNull ?? const [];
    final commesse = ref.watch(localCommesseProvider(customerId)).valueOrNull ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        BlamedFieldNotice(field: 'contractId', blamedField: widget.blamedField),
        ReferencePickerField(
          // Keyed by an epoch, not by the contract it shows. What may rebuild this field is a
          // *deliberate* change, and a keystroke is not one: `ReferencePickerField._onFreeText`
          // reports a pick released by editing the text through the same `onSelected(null)` as the
          // field's own X, so under a value key that release — the only way back to a suggestion list
          // once the field holds a pick — moved the key mid-edit and rebuilt the field under the
          // technician, wiping the character just typed. The value cannot tell a commit from a
          // keystroke; the epoch moves on the commits only. Same trick, same reason, as
          // `_prodottoPickerEpoch` in `step_dettagli_ticket.dart`.
          //
          // A rebuild the *state* asks for still has to be asked for here. The two branches below
          // that drop the customer (its own `onSelected`, and emptying its text) take the contract
          // out of state with `clearContractId: true` — and this widget would survive that, because
          // `AppLookupField` holds its own `_selectedId`/text and only ever *fills* text in, never
          // clears it. Without a bump the previous customer's contract name would stay on screen over
          // a null selection, on a field that edit mode draws read-only and therefore cannot be
          // corrected by typing. Both of those branches bump this epoch.
          key: ValueKey('contratto-$_contractPickerEpoch'),
          label: 'Contratto',
          localItems: contracts,
          search: (q) => search.searchContracts(customerId: customerId, query: q),
          selectedId: widget.state.contractId,
          hint: 'Cerca contratto…',
          emptyCacheHint: 'Nessun contratto in cache. Cerca per nome.',
          // Drawn but not offered when the caller cannot persist a change — see
          // [StepClienteSede.contractEditable]. `enabled: false` is what the widget already does
          // with a read-only field (an AbsorbPointer, so it cannot be typed into either), and the
          // caption below says why rather than leaving a dead field.
          enabled: widget.contractEditable,
          onSelected: (option) {
            if (option == null) {
              // A release — the X, or an edit that no longer represents a pick. It clears the id
              // (the picker's own contract: keeping the old id behind new text is how a ticket is
              // filed against the wrong contract) but it must NOT move the key, or the field
              // rebuilds under the technician and wipes what they are typing. The epoch moves on the
              // commits only.
              widget.onChanged(widget.state.copyWith(clearContractId: true));
              return;
            }
            // The search wrote the row into the mirror *before* returning it, so refetching the
            // local list here is enough for the summary to resolve a label for a row this device
            // only just learned about.
            ref.invalidate(localContractsProvider(customerId));
            setState(() => _contractPickerEpoch++);
            widget.onChanged(widget.state.copyWith(contractId: option.id));
          },
        ),
        if (!widget.contractEditable) const ReadOnlyFieldCaption(),
        const SizedBox(height: 20),
        BlamedFieldNotice(field: 'commessaId', blamedField: widget.blamedField),
        ReferencePickerField(
          // Keyed by an epoch, not by the commessa it shows — see the Contratto key above for why a
          // keystroke must not move a reference field's key.
          //
          // Three things move this epoch, and all three are deliberate: a pick (`onSelected` below);
          // a *refused* clear, which changes no state at all and so has no state change to rebuild
          // from (`onCleared` below, and the only gesture that bumps it); and the customer change in
          // `build` below, which takes the commessa out of state behind this field's back. Nothing
          // else.
          key: ValueKey('commessa-$_commessaPickerEpoch'),
          label: 'Commessa',
          localItems: commesse,
          search: (q) => search.searchCommesse(customerId: customerId, query: q),
          selectedId: widget.state.commessaId,
          hint: 'Cerca commessa…',
          emptyCacheHint: 'Nessuna commessa in cache. Cerca per codice.',
          onSelected: (option) {
            if (option == null) {
              // A release by editing the text is the technician searching for the next commessa, and
              // it is refused here the same way — but silently, because a toast per keystroke would
              // be a false error on a field they are only searching. See `onCleared` for the release
              // that is a real gesture and does say why.
              if (!widget.commessaClearable) return;
              widget.onChanged(widget.state.copyWith(clearCommessaId: true));
              return;
            }
            ref.invalidate(localCommesseProvider(customerId));
            setState(() => _commessaPickerEpoch++);
            widget.onChanged(widget.state.copyWith(commessaId: option.id));
          },
          // The re-key that makes a refused clear visible, on the one gesture that *is* a clear.
          //
          // A refusal deliberately changes no state, so there is nothing in the state for the field
          // to be rebuilt from and the box would keep sitting empty over the commessa the record
          // still holds. Only an *emptied* box bumps the epoch, which is why this is here and not in
          // the refusal above: that refusal is reached by two different gestures, and the other one —
          // releasing the pick by editing the text — is a search, not a clear. Rebuilding the field
          // under the technician then would wipe what they are typing, and typing is the only way in
          // to a suggestion list once a field already holds a pick.
          //
          // When the clear is allowed there is nothing to do: `onSelected`'s null branch above drops
          // the id, and the box is already empty — there is nothing on the field to rebuild.
          onCleared: () {
            if (!widget.commessaClearable) {
              showAppToast(
                context,
                message: 'La commessa non può essere rimossa da qui.',
                tone: ToastTone.error,
              );
              setState(() => _commessaPickerEpoch++);
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(allCustomersProvider);
    final customers = customersAsync.valueOrNull ?? [];

    // Filter locations by selected customer.
    final allLocationsAsync = ref.watch(allLocationsProvider);
    final allLocations = allLocationsAsync.valueOrNull ?? [];
    final locations = widget.state.customerId != null
        ? allLocations.where((l) => l.customerId == widget.state.customerId).toList()
        : <Location>[];

    final selectedCustomer = customers.where((c) => c.id == widget.state.customerId).firstOrNull;

    final selectedLocation = locations.where((l) => l.id == widget.state.locationId).firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      children: [
        // ── Customer ──────────────────────────────────────────────────────
        _SectionLabel(text: 'Cliente *'),
        const SizedBox(height: 8),
        BlamedFieldNotice(field: 'customerId', blamedField: widget.blamedField),
        AppLookupField(
          // Value can be reset externally (e.g. wizard back-navigation); key it by the value to
          // force a fresh widget — same reasoning the plain dropdown this replaces used to key
          // itself by, so an external reset is picked up via a fresh initialText/selectedId.
          key: ValueKey('cliente-${widget.state.customerId}'),
          label: 'Cliente *',
          hint: 'Cerca cliente…',
          items: [for (final c in customers) LookupItem(id: c.id, name: c.companyName)],
          selectedId: widget.state.customerId,
          onSelected: (id) {
            // The two reference fields are keyed by an epoch, so a change of customer — which takes
            // the contract, the commessa and the cantiere out of state just below — has to move those
            // epochs here. Under the value key that rebuild came for free; under an epoch it has to be
            // asked for, or the fields survive the change (`AppLookupField` holds its own
            // `_selectedId`/text and only ever *fills* text in) and go on showing the previous
            // customer's contract and commessa over a null selection. This is the request.
            setState(() {
              _contractPickerEpoch++;
              _commessaPickerEpoch++;
            });
            widget.onChanged(
              widget.state.copyWith(
                customerId: id,
                // The sede takes the explicit flag rather than a plain `locationId: null`: `copyWith`
                // reads a null argument as "not supplied" (`locationId: locationId ?? this.locationId`)
                // and hands the old sede straight back, so the reset this line intends never happened
                // and a ticket could be filed against the previous customer's sede.
                clearLocationId: true,
                // A contract, a commessa and a cantiere belong to the customer that owned them —
                // keeping one across a customer change would point the new ticket at a row the
                // server will refuse with a 404, and through the queue that is a ticket that never
                // arrives. Clearing here is the fix, not a detail. The sede above is the same class
                // of reference and clears for the same reason.
                clearContractId: true,
                clearCommessaId: true,
                clearCantiereId: true,
              ),
            );
          },
          // The customer here must resolve to a real cached record — unlike the rapportino's
          // Cliente field, NewTicketFormState has no free-text fallback (customerId is a plain
          // FK sent straight to the server). Cleared only when the field is actually emptied, not
          // on every keystroke of an in-progress edit: this field is keyed by customerId (above),
          // so clearing eagerly on a non-empty keystroke changed the key mid-edit and destroyed/
          // recreated the widget on every character typed — losing whatever had just been typed
          // and making it impossible to type over an already-resolved value at all.
          onFreeText: (text) {
            if (text.isEmpty) {
              // Same reasoning as onSelected above: the references are scoped to the customer
              // that is being dropped, so they go with it — and the epochs move with them.
              setState(() {
                _contractPickerEpoch++;
                _commessaPickerEpoch++;
              });
              widget.onChanged(
                widget.state.copyWith(
                  clearCustomerId: true,
                  clearLocationId: true,
                  clearContractId: true,
                  clearCommessaId: true,
                  clearCantiereId: true,
                ),
              );
            }
          },
        ),

        const SizedBox(height: 12),
        // An empty slot is drawn, not left blank. Before a customer is picked this is what the
        // step has to say — the field above is the only content, and the gap down to "Avanti"
        // used to read as unfinished rather than "not filled in yet".
        if (selectedCustomer != null)
          _CustomerSummary(customer: selectedCustomer)
        else
          const CompactEmptyState(
            label: 'Cliente non ancora selezionato',
            icon: LucideIcons.briefcase,
            height: 72,
          ),

        // ── Location ──────────────────────────────────────────────────────
        const SizedBox(height: 24),
        _SectionLabel(text: 'Sede *'),
        const SizedBox(height: 8),
        BlamedFieldNotice(field: 'locationId', blamedField: widget.blamedField),
        AppLookupField(
          // Same reasoning as the customer field above — the customer field's onSelected/
          // onFreeText reset locationId externally, so this must be rekeyed to pick up the reset.
          key: ValueKey('sede-${widget.state.locationId}'),
          label: 'Sede *',
          hint: widget.state.customerId != null
              ? 'Cerca sede o scrivi un nuovo indirizzo…'
              : 'Prima seleziona un cliente',
          items: [for (final l in locations) LookupItem(id: l.id, name: l.name)],
          selectedId: widget.state.locationId,
          initialText: _pendingSedeName,
          emptyCacheHint: widget.state.customerId == null
              ? 'Seleziona prima un cliente.'
              : 'Nessuna sede a catalogo: scrivi un indirizzo per crearne una nuova.',
          onSelected: (id) {
            _createLocationDebounce?.cancel();
            widget.onChanged(widget.state.copyWith(locationId: id));
          },
          // locationId is a plain FK (no free-text fallback field on NewTicketFormState), but
          // unlike Cliente above there is somewhere for genuinely new text to go: a real sede,
          // created for the selected client and then selected here — see _createNewLocation.
          onFreeText: (text) {
            _createLocationDebounce?.cancel();
            final trimmed = text.trim();
            if (trimmed.isEmpty) {
              widget.onChanged(widget.state.copyWith(clearLocationId: true));
              return;
            }
            final customerId = widget.state.customerId;
            // No client chosen yet — nothing to attach the new sede to. The hint above already
            // tells the technician to pick a client first; typing here just stands as plain text
            // until they do (same "not switched, nothing lost" behavior as everywhere else).
            if (customerId == null) return;
            _createLocationDebounce = Timer(
              const Duration(milliseconds: 900),
              () => _createNewLocation(customerId, trimmed),
            );
          },
        ),
        if (_creatingLocation)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Creazione nuova sede…',
                  style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),
        if (selectedLocation != null)
          _LocationSummary(location: selectedLocation)
        else if (widget.state.customerId != null)
          const CompactEmptyState(
            label: 'Sede non ancora selezionata',
            icon: LucideIcons.mapPin,
            height: 72,
          ),

        // ── Contratto / Commessa ───────────────────────────────────────────
        // Below the sede: these hang off the customer, and the customer is above.
        _buildReferences(),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Inline summary cards
// ══════════════════════════════════════════════════════════════════════════════

class _CustomerSummary extends StatelessWidget {
  const _CustomerSummary({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (customer.contactPerson != null && customer.contactPerson!.isNotEmpty)
            _InfoRow(label: 'Referente', value: customer.contactPerson!),
          if (customer.phone != null && customer.phone!.isNotEmpty)
            _InfoRow(label: 'Telefono', value: customer.phone!),
          if (customer.email != null && customer.email!.isNotEmpty)
            _InfoRow(label: 'Email', value: customer.email!),
        ],
      ),
    );
  }
}

class _LocationSummary extends StatelessWidget {
  const _LocationSummary({required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (location.address != null && location.address!.isNotEmpty) location.address!,
      if (location.city != null && location.city!.isNotEmpty) location.city!,
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (parts.isNotEmpty) _InfoRow(label: 'Indirizzo', value: parts.join(', ')),
          if (location.phone != null && location.phone!.isNotEmpty)
            _InfoRow(label: 'Telefono', value: location.phone!),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared small widgets
// ══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Archivo',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: context.colors.ink,
      ),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Text('$label: ', style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted)),
          Expanded(
            child: Text(value, style: AppTextStyles.bodySmall.copyWith(color: context.colors.ink)),
          ),
        ],
      ),
    );
  }
}
