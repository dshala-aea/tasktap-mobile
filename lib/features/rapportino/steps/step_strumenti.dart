// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../presentation/providers/strumenti_selection_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Strumenti — the instruments used on this rapportino
//
// Pre-filled once from the technician's own kit, then freely adjustable from the tenant
// catalogue (borrowing a colleague's instrument is normal). An instrument whose calibration
// expired before the work date needs an explicit "Confermo" — the same rule the server enforces
// (422 strumenti_invalid otherwise). Both lists come from the local mirror, so this works offline.
// Optional by nature: it does not count toward the completion card.
// ══════════════════════════════════════════════════════════════════════════════

/// 'yyyy-MM-dd' → 'dd/MM/yyyy'. Plain string work: a DateTime round trip would shift the day.
String formatCivilDate(String? civil) {
  if (civil == null || civil.length < 10) return civil ?? '';
  final p = civil.substring(0, 10).split('-');
  if (p.length != 3) return civil;
  return '${p[2]}/${p[1]}/${p[0]}';
}

class StepStrumenti extends ConsumerWidget {
  const StepStrumenti({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(strumentiSelectionProvider(reportId));
    final notifier = ref.read(strumentiSelectionProvider(reportId).notifier);

    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.base,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepLabel(title: 'Strumenti usati (${state.items.length})'),
          const SizedBox(height: 4),
          Text(
            'Gli strumenti del tuo kit sono già selezionati. Togli quelli non usati o aggiungine altri.',
            style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
          ),
          const SizedBox(height: 12),
          if (state.unacknowledgedExpired > 0) ...[
            InlineAlert(
              message: state.unacknowledgedExpired == 1
                  ? 'Uno strumento ha la taratura scaduta: conferma di averlo usato, '
                        'altrimenti l\'invio verrà rifiutato.'
                  : '${state.unacknowledgedExpired} strumenti hanno la taratura scaduta: '
                        'conferma di averli usati, altrimenti l\'invio verrà rifiutato.',
              color: context.colors.amber,
              icon: LucideIcons.alertCircle,
            ),
            const SizedBox(height: 12),
          ],
          if (state.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'Nessuno strumento selezionato.',
                style: TextStyle(color: context.colors.inkMuted),
              ),
            )
          else
            for (final item in state.items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _StrumentoCard(
                  key: ValueKey('strumento-card-${item.strumentoId}'),
                  item: item,
                  onRemove: () => notifier.remove(item.strumentoId),
                  onAcknowledge: (v) => notifier.setAcknowledged(item.strumentoId, v),
                  onUsageChanged: (v) => notifier.setUsageDescription(item.strumentoId, v),
                  onOutcomeChanged: (v) => notifier.setOutcome(item.strumentoId, v),
                ),
              ),
          const SizedBox(height: 8),
          AppButton.secondary(
            label: 'Aggiungi strumento',
            icon: const Icon(LucideIcons.plusSquare),
            onPressed: state.available.isEmpty
                ? null
                : () => _pickStrumento(context, state.available, notifier.add),
          ),
          if (state.available.isEmpty && state.items.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Nessuno strumento disponibile: il catalogo si scarica con la sincronizzazione.',
              style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickStrumento(
    BuildContext context,
    List<StrumentoRow> available,
    Future<void> Function(String id) onPick,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final s in available)
                ListTile(
                  // 56dp rows: gloved thumbs.
                  minTileHeight: 56,
                  leading: const Icon(LucideIcons.wrench),
                  title: Text(s.name),
                  subtitle: Text(
                    [
                      s.matricola,
                      if (s.isMine) 'nel tuo kit',
                      if (s.calibrationExpiry != null)
                        'taratura ${formatCivilDate(s.calibrationExpiry)}',
                    ].join(' · '),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    onPick(s.id);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Server limit of both notes (`strumento_usage_description_too_long` / `..._outcome_too_long`).
const int kStrumentoNoteMaxLength = 2000;

/// The character counter stays hidden until the note is close to the limit.
const int kStrumentoNoteCounterFrom = 1800;

class _StrumentoCard extends StatefulWidget {
  const _StrumentoCard({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onAcknowledge,
    required this.onUsageChanged,
    required this.onOutcomeChanged,
  });

  final StrumentoSelectionItem item;
  final VoidCallback onRemove;
  final ValueChanged<bool> onAcknowledge;
  final ValueChanged<String> onUsageChanged;
  final ValueChanged<String> onOutcomeChanged;

  @override
  State<_StrumentoCard> createState() => _StrumentoCardState();
}

class _StrumentoCardState extends State<_StrumentoCard> {
  // Created once from the stored note and then owned by the field: the selection state is reloaded
  // on every toggle/add/remove, and re-seeding from it would fight the cursor while typing. Each
  // keystroke is persisted at once (same as the other editor text fields).
  late final TextEditingController _usage = TextEditingController(
    text: widget.item.usageDescription,
  );
  late final TextEditingController _outcome = TextEditingController(text: widget.item.outcome);

  @override
  void dispose() {
    _usage.dispose();
    _outcome.dispose();
    super.dispose();
  }

  String? _counter(TextEditingController c) =>
      c.text.length >= kStrumentoNoteCounterFrom ? null : '';

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final onRemove = widget.onRemove;
    final onAcknowledge = widget.onAcknowledge;
    final c = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: c.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.matricola,
                      style: TextStyle(fontSize: 12, color: c.inkMuted),
                    ),
                    if (item.calibrationExpiry != null)
                      Text(
                        'Taratura valida fino al ${formatCivilDate(item.calibrationExpiry)}',
                        style: TextStyle(fontSize: 12, color: c.inkMuted),
                      ),
                    if (!item.inCatalogue)
                      Text(
                        'Non più in catalogo',
                        style: TextStyle(fontSize: 12, color: c.inkMuted),
                      ),
                  ],
                ),
              ),
              if (item.expired)
                AppBadge(label: 'Scaduto', outlined: true, fgColor: c.red),
              IconButton(
                tooltip: 'Rimuovi ${item.name}',
                // 48dp target.
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(LucideIcons.trash2),
                onPressed: onRemove,
              ),
            ],
          ),
          if (item.expired)
            InkWell(
              onTap: () => onAcknowledge(!item.expiredAcknowledged),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Confermo di aver usato questo strumento con la taratura scaduta',
                        style: TextStyle(fontSize: 13, color: c.ink),
                      ),
                    ),
                    AppToggle(value: item.expiredAcknowledged, onChanged: onAcknowledge),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField.multiline(
            key: ValueKey('strumento-usage-${item.strumentoId}'),
            label: 'Descrizione dell\'utilizzo',
            hint: 'Come hai usato lo strumento (facoltativo)',
            controller: _usage,
            maxLines: 4,
            maxLength: kStrumentoNoteMaxLength,
            counterText: _counter(_usage),
            onChanged: (v) {
              setState(() {});
              widget.onUsageChanged(v);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField.multiline(
            key: ValueKey('strumento-outcome-${item.strumentoId}'),
            label: 'Esito',
            hint: 'Risultato della misura o dell\'intervento (facoltativo)',
            controller: _outcome,
            maxLines: 4,
            maxLength: kStrumentoNoteMaxLength,
            counterText: _counter(_outcome),
            onChanged: (v) {
              setState(() {});
              widget.onOutcomeChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
