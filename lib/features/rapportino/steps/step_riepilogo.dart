// dart format width=100
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_message.dart';
// Uses StepLabel — the padding-free sibling of SectionTitle, for headings inside a padded card.
import '../../../data/local/app_database.dart';
import '../../../data/sync/draft_submission_state.dart';
import '../../../data/sync/submission_queue_watcher.dart';
import '../../../domain/reports/draft_validation.dart';
import '../../../presentation/providers/report_editor_providers.dart';
import '../../../presentation/providers/schedule_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 4 — Riepilogo
//
// KeyVal summary of the draft + firma cliente/tecnico pads +
// validateDraft().italianMessages + "Invia rapportino" submit flow.
// Submit logic mirrors old step_review.dart exactly.
// ══════════════════════════════════════════════════════════════════════════════

class StepRiepilogo extends ConsumerStatefulWidget {
  const StepRiepilogo({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<StepRiepilogo> createState() => _StepRiepilogoState();
}

class _StepRiepilogoState extends ConsumerState<StepRiepilogo> {
  bool _submitting = false;
  String? _submitError;

  Future<void> _onInvia() async {
    final queue = ref.read(realSubmissionQueueProvider);
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await queue.enqueue(widget.reportId);
      await queue.processAll();
    } catch (e) {
      // The red line under the submit button. It printed `e.toString()`, which put a Dio stack at
      // the exact moment two people have just signed and the only question is whether the record
      // survived.
      setState(() => _submitError = humanErrorMessage(e, azione: 'inviare il rapportino'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The customer as a person would name it: the cached company name, else what was typed.
  ///
  /// Falls back to the free text rather than the id — an unresolvable id is not worth printing,
  /// and a name typed by hand is still the answer to "who is this for".
  static String _customerLabel(WidgetRef ref, ReportEditorState state) {
    final id = state.customerId;
    if (id != null && id.isNotEmpty) {
      for (final c in ref.watch(allCustomersProvider).valueOrNull ?? const <Customer>[]) {
        if (c.id == id) return c.companyName;
      }
    }
    final typed = state.customerFreeText;
    return (typed?.isNotEmpty ?? false) ? typed! : '—';
  }

  /// Ticket or cantiere as one line. They are alternatives, so four rows for them was three too
  /// many, and "(lib.)" was internal vocabulary for a distinction the reader does not have.
  static String? _riferimento(WidgetRef ref, ReportEditorState state) {
    final ticketId = state.ticketId;
    if (ticketId != null && ticketId.isNotEmpty) {
      for (final t in ref.watch(allTicketsProvider).valueOrNull ?? const <Ticket>[]) {
        if (t.id == ticketId) return 'Ticket · ${t.title}';
      }
    }
    final cantiereId = state.cantiereId;
    if (cantiereId != null && cantiereId.isNotEmpty) {
      for (final c in ref.watch(allCantieriProvider).valueOrNull ?? const <CantieriData>[]) {
        if (c.id == cantiereId) return 'Cantiere · ${c.name}';
      }
    }
    if (state.ticketFreeText?.isNotEmpty ?? false) return 'Ticket · ${state.ticketFreeText}';
    if (state.cantiereFreeText?.isNotEmpty ?? false) return 'Cantiere · ${state.cantiereFreeText}';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportEditorProvider(widget.reportId));
    final repo = ref.watch(draftReportRepositoryProvider);
    final validation = state.validation;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(19, 16, 19, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Validation panel ───────────────────────────────────────────────
          if (!validation.isValid) ...[
            _ValidationPanel(validation: validation),
            const SizedBox(height: 16),
          ],

          // ── Summary ────────────────────────────────────────────────────────
          //
          // This card is the last thing read before two people sign. It used to print raw GUIDs:
          // `Cliente  3f2a1c8e-…`, and separate `Ticket` / `Ticket (lib.)` rows for what is one
          // fact stored two ways. Nobody can check a rapportino against a GUID, so the step that
          // exists to be checked could not be.
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                KeyVal(label: 'Titolo', value: state.title.isEmpty ? '—' : state.title),
                // Stated on the page the technician signs off, not only in a database column.
                // They are attesting to this record; they should be able to see that part of it
                // was drafted for them.
                if (state.isAiAssisted)
                  const KeyVal(label: 'Redazione', value: 'Bozza generata con AI, poi rivista'),
                KeyVal(label: 'Cliente', value: _customerLabel(ref, state)),
                KeyVal(label: 'Indirizzo', value: state.workAddress ?? '—'),
                if (_riferimento(ref, state) case final riferimento?)
                  KeyVal(label: 'Riferimento', value: riferimento),
                KeyVal(label: 'Tecnici', value: '${state.staffRows.length}'),
                KeyVal(
                  label: 'Ore totali',
                  value:
                      '${state.staffRows.fold<double>(0, (s, r) => s + r.effectiveHours).toStringAsFixed(1)} h',
                ),
                KeyVal(
                  label: 'Materiali',
                  value: state.materialiNotRequired ? 'Nessuno' : '${state.materialeRows.length}',
                ),
                KeyVal(
                  label: 'Foto',
                  value: '${state.allegatoRows.where((a) => !a.isSignature).length}',
                  showDivider: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Firma cliente ──────────────────────────────────────────────────
          StepLabel(title: 'Firma cliente *'),
          const SizedBox(height: 8),
          _SignatureBlock(
            label: 'cliente',
            allegatoId: state.customerSignatureAllegatoId,
            localPath: state.customerSignatureLocalPath,
            isCustomer: true,
            reportId: widget.reportId,
          ),
          const SizedBox(height: 20),

          // ── Firma tecnico ──────────────────────────────────────────────────
          StepLabel(title: 'Firma tecnico *'),
          const SizedBox(height: 8),
          _SignatureBlock(
            label: 'tecnico',
            allegatoId: state.technicianSignatureAllegatoId,
            localPath: state.technicianSignatureLocalPath,
            isCustomer: false,
            reportId: widget.reportId,
          ),
          const SizedBox(height: 24),

          // ── Submission state + Invia button ────────────────────────────────
          StreamBuilder<DraftReport?>(
            stream: repo.watchDraft(widget.reportId),
            builder: (context, snap) {
              final draft = snap.data;
              final subState = DraftSubmissionState.fromString(draft?.submissionState ?? 'draft');

              if (subState == DraftSubmissionState.submitted) {
                return _StatusCard(
                  color: context.colors.green,
                  icon: LucideIcons.checkCircle2,
                  title: 'Rapportino inviato con successo.',
                );
              }

              if (subState == DraftSubmissionState.uploadingMedia ||
                  subState == DraftSubmissionState.submitting) {
                return _StatusCard(
                  color: context.colors.blue,
                  icon: LucideIcons.refreshCw,
                  title: subState == DraftSubmissionState.uploadingMedia
                      ? 'Caricamento media in corso...'
                      : 'Invio rapportino...',
                  showProgress: true,
                );
              }

              if (subState == DraftSubmissionState.failed) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusCard(
                      color: context.colors.red,
                      icon: LucideIcons.alertCircle,
                      title: 'Invio fallito',
                      subtitle: draft?.submissionError,
                    ),
                    const SizedBox(height: 12),
                    AppButton.danger(
                      label: 'Riprova invio',
                      icon: const Icon(LucideIcons.refreshCw),
                      onPressed: _submitting ? null : _onInvia,
                      isLoading: _submitting,
                      size: AppButtonSize.lg,
                    ),
                  ],
                );
              }

              // Draft state — show validation + invia button
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (validation.isValid)
                    _StatusCard(
                      color: context.colors.green,
                      icon: LucideIcons.checkCircle2,
                      title: 'Pronto per l\'invio',
                      subtitle: 'Il rapportino è completo e pronto per essere inviato.',
                    ),
                  if (_submitError != null) ...[
                    const SizedBox(height: 8),
                    Text(_submitError!, style: TextStyle(color: context.colors.red, fontSize: 12)),
                  ],
                  const SizedBox(height: 12),
                  AppButton(
                    label: _submitting ? 'Invio in corso...' : 'Invia rapportino',
                    icon: _submitting ? null : const Icon(LucideIcons.send),
                    onPressed: validation.isValid && !_submitting ? _onInvia : null,
                    isLoading: _submitting,
                    size: AppButtonSize.lg,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Validation panel ──────────────────────────────────────────────────────────

class _ValidationPanel extends StatelessWidget {
  const _ValidationPanel({required this.validation});

  final DraftValidationResult validation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // A tint of the theme's own amber, not a fixed cream. The panel was #FFF8E1 while every
        // line of text inside it takes `context.colors.ink` — which is near-white in dark mode.
        // The result was white text on cream, on the one panel that lists what is blocking the
        // technician from submitting.
        color: context.colors.amber.withValues(alpha: 0.12),
        border: Border.all(color: context.colors.amber),
        borderRadius: AppRack.freeShape,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: context.colors.amber, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Da completare prima dell\'invio:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final msg in validation.italianMessages)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.circle, size: 6, color: context.colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(msg, style: TextStyle(color: context.colors.ink, fontSize: 14)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.color,
    required this.icon,
    required this.title,
    this.subtitle,
    this.showProgress = false,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final bg = color.withAlpha(20);
    final border = color.withAlpha(80);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          showProgress
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              : Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(color: color, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Signature block ───────────────────────────────────────────────────────────

class _SignatureBlock extends ConsumerWidget {
  const _SignatureBlock({
    required this.label,
    required this.allegatoId,
    required this.localPath,
    required this.isCustomer,
    required this.reportId,
  });

  final String label;
  final String? allegatoId;
  final String? localPath;
  final bool isCustomer;
  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captured = localPath != null && allegatoId != null;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (captured) ...[
            // Show captured image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(localPath!),
                height: 120,
                fit: BoxFit.contain,
                errorBuilder: (ctx, e, _) =>
                    Icon(LucideIcons.imageOff, color: context.colors.inkMuted, size: 40),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(LucideIcons.checkCircle2, color: context.colors.green, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Firma acquisita',
                    style: TextStyle(color: context.colors.green, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () => _clearSig(ref),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: Text('Cancella', style: TextStyle(color: context.colors.red)),
                ),
              ],
            ),
          ] else ...[
            // Dashed empty area
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: context.colors.bg2,
                border: Border.all(color: context.colors.borderStrong, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'Firma $label non acquisita',
                  style: TextStyle(color: context.colors.inkMuted, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 10),
            AppButton(
              label: 'Acquisisci firma $label',
              icon: const Icon(LucideIcons.penTool),
              onPressed: () => _captureSig(context, ref),
              size: AppButtonSize.lg,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _captureSig(BuildContext context, WidgetRef ref) async {
    final bytes = await showDialog<Uint8List?>(
      context: context,
      builder: (_) => const _SigDialog(),
    );
    if (bytes == null || bytes.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    final id =
        '${isCustomer ? 'sig-cliente' : 'sig-tecnico'}-${DateTime.now().millisecondsSinceEpoch}';
    final file = File('${dir.path}/$id.png');
    await file.writeAsBytes(bytes);

    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    if (isCustomer) {
      await notifier.saveCustomerSignature(allegatoId: id, bytes: bytes, localPath: file.path);
    } else {
      await notifier.saveTechnicianSignature(allegatoId: id, bytes: bytes, localPath: file.path);
    }
  }

  Future<void> _clearSig(WidgetRef ref) async {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    if (isCustomer) {
      await notifier.clearCustomerSignature();
    } else {
      await notifier.clearTechnicianSignature();
    }
  }
}

// ── Signature capture dialog (identical to step_firme._SignatureCaptureDialog) ─

class _SigDialog extends StatefulWidget {
  const _SigDialog();

  @override
  State<_SigDialog> createState() => _SigDialogState();
}

class _SigDialogState extends State<_SigDialog> {
  late final SignatureController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = SignatureController(
      penStrokeWidth: 3,
      penColor: context.colors.ink,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Column(
        children: [
          // Stays an AppBar, unlike the ten screen headers converted to ScreenHeaderBar. This is a
          // full-screen modal dismissed with an X, not a screen navigated back from, and
          // ScreenHeader draws a back chevron — the wrong affordance for a sheet you cancel.
          //
          // Its ink is fixed rather than themed for the usual reason: the bar is CHARCOAL under
          // both themes, and `inkInverse` flipped to near-black, taking the title and the close
          // button off the dialog that captures the customer's signature.
          AppBar(
            backgroundColor: AppColors.CHARCOAL,
            foregroundColor: AppColors.onDark,
            title: const Text('Acquisisci firma'),
            leading: IconButton(
              icon: const Icon(LucideIcons.x),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              TextButton(
                onPressed: () => _ctrl.clear(),
                child: Text('Cancella', style: TextStyle(color: context.colors.inkMuted)),
              ),
              TextButton(
                onPressed: () async {
                  if (_ctrl.isEmpty) {
                    Navigator.pop(context);
                    return;
                  }
                  final bytes = await _ctrl.toPngBytes();
                  if (context.mounted) {
                    Navigator.pop(context, bytes);
                  }
                },
                child: const Text(
                  'Conferma',
                  style: TextStyle(color: AppColors.Y, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Firma nell\'area sottostante',
              style: TextStyle(color: context.colors.inkMuted),
            ),
          ),
          Expanded(
            child: Signature(controller: _ctrl, backgroundColor: context.colors.bg1),
          ),
        ],
      ),
    );
  }
}
