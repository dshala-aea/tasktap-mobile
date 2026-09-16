// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../data/extension_fields/extension_fields_api_client.dart';
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

class ExtensionFieldsSection extends ConsumerStatefulWidget {
  const ExtensionFieldsSection({super.key, required this.entityType, required this.entityId});

  /// The backend's own lowercase entity-type key — 'ticket', 'cantiere', 'report',
  /// 'cantiereworklog', … — see `ExtensionFieldsController.DispatchGetAsync`'s dispatch table for
  /// the exact set this must match.
  final String entityType;

  final String entityId;

  @override
  ConsumerState<ExtensionFieldsSection> createState() => _ExtensionFieldsSectionState();
}

class _ExtensionFieldsSectionState extends ConsumerState<ExtensionFieldsSection> {
  /// Live text for text/number fields.
  final Map<String, TextEditingController> _controllers = {};

  /// Current value for date/boolean/select fields — these have no natural TextEditingController,
  /// so their working state lives here instead, keyed the same way as [_controllers].
  final Map<String, String> _otherValues = {};

  /// Populated once, from the first successful defs+values load — see [_seed]. Re-fetches after
  /// that (e.g. a pull elsewhere invalidating the provider) do not re-seed and blow away whatever
  /// the technician has typed since.
  List<ExtensionFieldDefinitionDto>? _defs;

  bool _dirty = false;
  bool _isSaving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(List<ExtensionFieldDefinitionDto> defs, Map<String, String> values) {
    if (_defs != null) return;
    _defs = defs;
    for (final d in defs) {
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

  String _valueFor(String key) => _controllers[key]?.text ?? _otherValues[key] ?? '';

  void _setOther(String key, String value) {
    setState(() {
      _otherValues[key] = value;
      _dirty = true;
    });
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
    final defsAsync = ref.watch(extensionFieldDefinitionsProvider(widget.entityType));

    return defsAsync.when(
      // Loading/error both render nothing: this section is supplementary to whatever primary form
      // hosts it, and a failed or slow fetch of a feature most entities don't even use must never
      // block or clutter the fields the technician actually came here for.
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (defs) {
        if (defs.isEmpty) return const SizedBox.shrink();

        final valuesKey = (widget.entityType, widget.entityId);
        final valuesAsync = ref.watch(extensionFieldValuesProvider(valuesKey));

        return valuesAsync.when(
          loading: () => _buildLoading(context),
          error: (e, _) => _buildError(context, valuesKey),
          data: (values) {
            _seed(defs, values);
            return _buildSection(context, _defs!);
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

  Widget _buildError(BuildContext context, (String, String) valuesKey) {
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
                TextButton(
                  onPressed: () => ref.invalidate(extensionFieldValuesProvider(valuesKey)),
                  child: const Text('Riprova'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, List<ExtensionFieldDefinitionDto> defs) {
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
                for (final d in defs) ...[_buildField(context, d), const SizedBox(height: 16)],
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

  Widget _buildField(BuildContext context, ExtensionFieldDefinitionDto d) {
    switch (d.renderType) {
      case ExtensionFieldRenderType.number:
        return AppTextField(
          label: _labelFor(d),
          hint: d.placeholder,
          controller: _controllers[d.key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          onChanged: (_) => setState(() => _dirty = true),
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
              onChanged: (v) => _setOther(d.key, v.toString()),
            ),
          ],
        );

      case ExtensionFieldRenderType.date:
        return _DateField(
          label: _labelFor(d),
          value: _otherValues[d.key] ?? '',
          onChanged: (v) => _setOther(d.key, v),
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
            onChanged: (_) => setState(() => _dirty = true),
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
            onChanged: (v) => v != null ? _setOther(d.key, v) : null,
          ),
        );

      case ExtensionFieldRenderType.text:
        return AppTextField(
          label: _labelFor(d),
          hint: d.placeholder,
          controller: _controllers[d.key],
          onChanged: (_) => setState(() => _dirty = true),
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
  const _DateField({required this.label, required this.value, required this.onChanged});

  final String label;

  /// The stored value — an ISO 'yyyy-MM-dd' string, or empty when unset.
  final String value;

  /// Called with a new ISO 'yyyy-MM-dd' string.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final parsed = value.isEmpty ? null : DateTime.tryParse(value);
    final display = parsed != null ? DateFormat('dd/MM/yyyy').format(parsed) : 'Seleziona data';

    return AppFieldShell(
      label: label,
      child: AppTappable(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: parsed ?? DateTime.now(),
            firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
            lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
          );
          if (picked != null) {
            onChanged(DateFormat('yyyy-MM-dd').format(picked));
          }
        },
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
