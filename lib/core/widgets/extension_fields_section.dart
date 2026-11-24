// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../data/extension_fields/extension_fields_api_client.dart';
import '../../data/sync/connectivity_provider.dart';
import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../utils/error_message.dart';
import 'app_button.dart';
import 'app_card.dart';
import 'app_tappable.dart';
import 'app_text_field.dart';
import 'app_toast.dart';
import 'app_toggle.dart';
import 'section_title.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ExtensionFieldsSection
//
// "Altri campi" — renders whatever custom fields a tenant admin configured for an entity type
// (web-only config UI, backend `ExtensionFieldsController`) and lets the technician fill them in
// on the entity's own mobile form. Self-contained: it fetches its own definitions/values and saves
// with its own button, independent of whatever save flow the surrounding screen already has — the
// surrounding form's own fields and this section's fields are two different PUTs to two different
// endpoints, and folding them into one submit would mean every host screen learning this section's
// internals. A host screen just drops this in near the bottom of its form and otherwise ignores it.
//
// Renders nothing at all (not even a heading) when the tenant has no active definitions for this
// entity type — most tenants, most of the time — so a screen that includes this unconditionally
// costs nothing visually until an admin actually configures something.
//
// Requires an existing [entityId]: the values endpoint is `PUT /extension-fields/{type}/{id}/
// values`, so there is nothing to attach values to before the entity itself has been created.
// Host screens that both create and edit the same entity (e.g. AdminCantiereFormScreen) should
// only mount this once editing an existing one, not while creating a new one.
// ══════════════════════════════════════════════════════════════════════════════

/// Where a draft entity keeps its custom-field values on this device — see
/// [ExtensionFieldsSection.localStore].
abstract class ExtensionValuesStore {
  Future<Map<String, String>> load();
  Future<void> save(Map<String, String> values);
}

class ExtensionFieldsSection extends ConsumerStatefulWidget {
  const ExtensionFieldsSection({
    super.key,
    required this.entityType,
    required this.entityId,
    this.canEdit = true,
    this.localStore,
  });

  /// The backend's own lowercase entity-type key — 'ticket', 'cantiere', 'report',
  /// 'cantiereworklog', … — see `ExtensionFieldsController.DispatchGetAsync`'s dispatch table for
  /// the exact set this must match.
  final String entityType;

  final String entityId;

  /// Whether the signed-in seat may write these values. False renders the section read-only (no
  /// save control and no editable fields) instead of offering a save the server would refuse.
  final bool canEdit;

  /// Set for an entity that exists only on this device until it is submitted (a rapportino draft):
  /// its values are read from and written to [localStore] — no network, so the section behaves the
  /// same online and offline — instead of the `/extension-fields/.../values` endpoints, which would
  /// 404 for a row the server has never seen. There is no Save button in this mode: edits are
  /// stored as the technician types and travel with the entity's own submit.
  final ExtensionValuesStore? localStore;

  @override
  ConsumerState<ExtensionFieldsSection> createState() => _ExtensionFieldsSectionState();
}

class _ExtensionFieldsSectionState extends ConsumerState<ExtensionFieldsSection> {
  /// Live text for text/number fields.
  final Map<String, TextEditingController> _controllers = {};

  /// Current value for date/boolean/select fields — these have no natural TextEditingController,
  /// so their working state lives here instead, keyed the same way as [_controllers].
  final Map<String, String> _otherValues = {};

  /// The latest definitions (see [_sync]).
  List<ExtensionFieldDefinitionDto>? _defs;

  bool _dirty = false;
  bool _isSaving = false;

  bool get _local => widget.localStore != null;

  /// Local mode: the values the store held when the section opened, null until loaded.
  Map<String, String>? _localValues;
  Object? _localError;
  Timer? _localSaveTimer;

  @override
  void initState() {
    super.initState();
    if (_local) unawaited(_loadLocal());
  }

  Future<void> _loadLocal() async {
    try {
      final values = await widget.localStore!.load();
      if (!mounted) return;
      setState(() {
        _localValues = values;
        _localError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _localError = e);
    }
  }

  @override
  void dispose() {
    // A pending debounced save must not be lost when the step is left within its window.
    if (_localSaveTimer?.isActive ?? false) {
      _localSaveTimer!.cancel();
      unawaited(_saveLocal());
    }
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Reconciles the working state with the latest [defs], key by key. The definitions can change
  /// while the form is open — the device's mirror is shown first and the live list replaces it a
  /// moment later, or the office edits a field — so this runs on every emission, not once:
  /// a field that appears is seeded (stored value, else its default), one that vanished is dropped,
  /// and a field that was already there keeps exactly what the technician typed.
  void _sync(List<ExtensionFieldDefinitionDto> defs, Map<String, String> values) {
    _defs = defs;
    final keys = {for (final d in defs) d.key};
    for (final gone in _controllers.keys.where((k) => !keys.contains(k)).toList()) {
      _controllers.remove(gone)?.dispose();
    }
    _otherValues.removeWhere((k, _) => !keys.contains(k));

    for (final d in defs) {
      if (_controllers.containsKey(d.key) || _otherValues.containsKey(d.key)) continue;
      final raw = values[d.key] ?? d.defaultValue ?? '';
      switch (d.renderType) {
        case ExtensionFieldRenderType.text:
        case ExtensionFieldRenderType.number:
          _controllers[d.key] = TextEditingController(text: raw);
        case ExtensionFieldRenderType.date:
        case ExtensionFieldRenderType.boolean:
        case ExtensionFieldRenderType.select:
          _otherValues[d.key] = raw;
      }
    }
  }

  void _markDirty() {
    setState(() => _dirty = true);
    if (_local) {
      _localSaveTimer?.cancel();
      _localSaveTimer = Timer(const Duration(milliseconds: 400), () => unawaited(_saveLocal()));
    }
  }

  Future<void> _saveLocal() async {
    final defs = _defs;
    final store = widget.localStore;
    if (defs == null || store == null) return;
    try {
      await store.save({for (final d in defs) d.key: _valueFor(d.key)});
    } catch (_) {
      // Best effort: the next edit retries, and the pre-submit check reads what was stored.
    }
  }

  String _valueFor(String key) => _controllers[key]?.text ?? _otherValues[key] ?? '';

  void _setOther(String key, String value) {
    _otherValues[key] = value;
    _markDirty();
  }

  Future<void> _save() async {
    final defs = _defs;
    if (defs == null || _isSaving) return;

    setState(() => _isSaving = true);
    final values = {for (final d in defs) d.key: _valueFor(d.key)};

    try {
      await ref
          .read(extensionFieldsApiClientProvider)
          .saveValues(widget.entityType, widget.entityId, values);
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _dirty = false;
      });
      showAppToast(context, message: 'Campi aggiuntivi salvati', tone: ToastTone.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showAppToast(
        context,
        message: humanErrorMessage(e, azione: 'salvare i campi aggiuntivi'),
        tone: ToastTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Offline, a type whose values the mirror does not carry would render every field blank in
    // read-only mode with a "sola lettura" note — which reads as "this asset has no custom fields"
    // when the truth is that the values never reached this device. Rendering nothing is the honest
    // answer; the fields come back with the connection, not with a stale empty copy. A local draft
    // is exempt: its values ARE on this device.
    if (!_local &&
        !ref.watch(isOnlineProvider) &&
        !mirroredExtensionValueEntityTypes.contains(widget.entityType)) {
      return const SizedBox.shrink();
    }

    final defsAsync = _local
        ? ref.watch(extensionFieldDefinitionsFreshProvider(widget.entityType))
        : ref.watch(extensionFieldDefinitionsProvider(widget.entityType));

    void retryDefinitions() {
      if (_local) {
        ref.invalidate(extensionFieldDefinitionsFreshProvider(widget.entityType));
      } else {
        ref.invalidate(extensionFieldDefinitionsProvider(widget.entityType));
      }
    }

    return defsAsync.when(
      // Loading renders nothing: this section is supplementary to whatever primary form hosts it,
      // and a slow fetch of a feature most entities don't even use must never block or clutter the
      // fields the technician actually came here for. A FAILED load is different — it used to
      // vanish just as silently, which read as "this tenant has no custom fields" — so it says so
      // and offers a retry.
      loading: () => const SizedBox.shrink(),
      error: (e, _) => _buildError(context, onRetry: retryDefinitions),
      data: (defs) {
        if (defs.isEmpty) return const SizedBox.shrink();

        if (_local) {
          if (_localError != null) {
            return _buildError(context, onRetry: () => unawaited(_loadLocal()));
          }
          final values = _localValues;
          if (values == null) return _buildLoading(context);
          _sync(defs, values);
          return _buildSection(context, defs);
        }

        final valuesKey = (widget.entityType, widget.entityId);
        final valuesAsync = ref.watch(extensionFieldValuesProvider(valuesKey));

        return valuesAsync.when(
          loading: () => _buildLoading(context),
          error: (e, _) => _buildError(
            context,
            onRetry: () => ref.invalidate(extensionFieldValuesProvider(valuesKey)),
          ),
          data: (values) {
            _sync(defs, values);
            return _buildSection(context, defs);
          },
        );
      },
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StepLabel(title: 'Altri campi'),
          const SizedBox(height: 10),
          const AppCard(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, {required VoidCallback onRetry}) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StepLabel(title: 'Altri campi'),
          const SizedBox(height: 10),
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Impossibile caricare i campi aggiuntivi.',
                    style: TextStyle(fontSize: 13, color: context.colors.inkMuted),
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('Riprova')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, List<ExtensionFieldDefinitionDto> defs) {
    // Offline the section is READ-ONLY: the values render from the sync mirror (so a technician
    // can still see what the office recorded), but saving them needs a connection, and there is no
    // queued-write path for this endpoint. Hiding the button is the honest affordance — the
    // alternative is letting a technician type into fields whose save will fail and take the text
    // with it. This is exactly the case that used to be invisible: the whole section simply did not
    // appear offline. A seat without the entity's write capability gets the same treatment, even
    // online: the fields are shown, but there is no actionable save to refuse.
    final online = ref.watch(isOnlineProvider);
    final editable = (_local || online) && widget.canEdit;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StepLabel(title: 'Altri campi'),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in defs) ...[
                  _buildField(context, d, editable: editable),
                  const SizedBox(height: 16),
                ],
                if (!editable)
                  Text(
                    (_local || online)
                        ? 'Sola lettura: non hai i permessi per modificare questi campi.'
                        : 'Sola lettura finché non torna la connessione.',
                    style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
                  )
                else if (_local)
                  Text(
                    'Salvati su questo dispositivo e inviati con il rapporto di intervento.',
                    style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
                  )
                else
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton(
                      label: _isSaving ? 'Salvataggio…' : 'Salva',
                      onPressed: (!_dirty || _isSaving) ? null : _save,
                      isLoading: _isSaving,
                      size: AppButtonSize.sm,
                      fullWidth: false,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [d.label] with the same trailing-asterisk convention [AppFieldLabel] parses everywhere else
  /// in the app — required fields mark themselves the same way regardless of which entity's form
  /// they showed up on.
  String _labelFor(ExtensionFieldDefinitionDto d) => d.isRequired ? '${d.label} *' : d.label;

  Widget _buildField(
    BuildContext context,
    ExtensionFieldDefinitionDto d, {
    required bool editable,
  }) {
    switch (d.renderType) {
      case ExtensionFieldRenderType.number:
        return AppTextField(
          label: _labelFor(d),
          hint: d.placeholder,
          controller: _controllers[d.key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          readOnly: !editable,
          onChanged: (_) => _markDirty(),
          suffixIcon: (d.unit != null && d.unit!.isNotEmpty)
              ? Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: Align(
                    alignment: Alignment.centerRight,
                    widthFactor: 1,
                    child: Text(
                      d.unit!,
                      style: TextStyle(fontSize: 13, color: context.colors.inkMuted),
                    ),
                  ),
                )
              : null,
        );

      case ExtensionFieldRenderType.boolean:
        return Row(
          children: [
            Expanded(child: AppFieldLabel(label: d.label, enabled: true)),
            AppToggle(
              value: _otherValues[d.key] == 'true',
              onChanged: editable ? (v) => _setOther(d.key, v.toString()) : null,
            ),
          ],
        );

      case ExtensionFieldRenderType.date:
        return _DateField(
          label: _labelFor(d),
          value: _otherValues[d.key] ?? '',
          onChanged: (v) => _setOther(d.key, v),
          enabled: editable,
        );

      case ExtensionFieldRenderType.select:
        final choices = d.choiceOptions;
        // No usable choice list — falls back to a plain text field rather than rendering a
        // dropdown with nothing selectable in it (see this widget's own class doc comment on
        // "fall back to a plain text field for an unrecognized type"; an unparsable Options string
        // is the same situation in practice).
        if (choices.isEmpty) {
          return AppTextField(
            label: _labelFor(d),
            hint: d.placeholder,
            controller: _controllers.putIfAbsent(
              d.key,
              () => TextEditingController(text: _otherValues[d.key] ?? ''),
            ),
            readOnly: !editable,
            onChanged: (_) => _markDirty(),
          );
        }
        final current = _otherValues[d.key];
        return AppFieldShell(
          label: _labelFor(d),
          child: DropdownButtonFormField<String>(
            key: ValueKey('ext-${d.key}-$current'),
            initialValue: (current != null && choices.contains(current)) ? current : null,
            isExpanded: true,
            decoration: InputDecoration(hintText: d.placeholder ?? 'Seleziona…'),
            items: [for (final c in choices) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: editable ? (v) => v != null ? _setOther(d.key, v) : null : null,
          ),
        );

      case ExtensionFieldRenderType.text:
        return AppTextField(
          label: _labelFor(d),
          hint: d.placeholder,
          controller: _controllers[d.key],
          readOnly: !editable,
          onChanged: (_) => _markDirty(),
        );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _DateField — same AppFieldShell + tappable-row-with-icon shape as admin's own AdminDateField
// (lib/features/admin/admin_widgets.dart), reimplemented here rather than imported: that widget is
// feature-local (admin), and this is a core/ widget every feature can use.
// ══════════════════════════════════════════════════════════════════════════════

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;

  /// The stored value — an ISO 'yyyy-MM-dd' string, or empty when unset.
  final String value;

  /// Called with a new ISO 'yyyy-MM-dd' string.
  final ValueChanged<String> onChanged;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final parsed = value.isEmpty ? null : DateTime.tryParse(value);
    final display = parsed != null ? DateFormat('dd/MM/yyyy').format(parsed) : 'Seleziona data';

    return AppFieldShell(
      label: label,
      child: AppTappable(
        onTap: enabled
            ? () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: parsed ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                );
                if (picked != null) {
                  onChanged(DateFormat('yyyy-MM-dd').format(picked));
                }
              }
            : null,
        color: c.bg3,
        border: Border.all(color: c.borderLight),
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
        semanticLabel: '$label: $display',
        child: Row(
          children: [
            Expanded(
              child: Text(
                display,
                style: TextStyle(fontSize: 14, color: parsed != null ? c.ink : c.inkMuted),
              ),
            ),
            Icon(LucideIcons.calendar, size: 16, color: c.inkMuted),
          ],
        ),
      ),
    );
  }
}
