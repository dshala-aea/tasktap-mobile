// dart format width=100
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../data/users/user_signature_api_client.dart';
import '../../../domain/reports/draft_validation.dart';
import '../../../presentation/providers/report_editor_providers.dart';
import '../../../presentation/providers/schedule_providers.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

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

  // Opened once, not re-called from build() — build() runs on every setState during submit
  // (_submitting flips twice per _onInvia), and calling repo.watchDraft(...) inline there tore
  // down and reopened the underlying DB stream on each of those, instead of just re-subscribing
  // a StreamBuilder to the stream already in flight.
  late final Stream<DraftReport?> _draftStream = ref
      .read(draftReportRepositoryProvider)
      .watchDraft(widget.reportId);

  @override
  void initState() {
    super.initState();
    unawaited(_maybePrefillTechnicianSignature());
  }

  /// Pre-fills "Firma tecnico" from the technician's own saved signature (see
  /// `UserSignatureApiClient`), so a returning technician doesn't have to redraw the same
  /// signature on every rapportino.
  ///
  /// Waits for hydration (`notifier.ready`) before checking: for a *resumed* draft, the initial
  /// `ReportEditorState` is just a placeholder until hydration loads the real saved signature (if
  /// any) from Drift, and checking before that would risk overwriting it with a stale
  /// network fetch racing the local read. For a genuinely new rapportino, hydration is a fast
  /// no-op (no matching Drift row).
  ///
  /// Two guards, both checked before *and* after the network fetch (a resumed draft's hydration,
  /// a manual capture, or a deliberate Cancella can all complete while that fetch is in flight):
  ///   - `technicianSignatureAllegatoId != null` — already captured, nothing to pre-fill.
  ///   - `technicianSignaturePrefillSuppressed` — the technician explicitly cleared their
  ///     signature via "Cancella" on *this* draft. `StepRiepilogo` is recreated (fresh
  ///     `initState`) every time its containing bottom sheet reopens, so without this persisted
  ///     flag, closing and reopening after a deliberate Cancella would silently re-fetch and
  ///     reinstate the exact signature just removed. See
  ///     `DraftReports.technicianSignaturePrefillSuppressed`'s own doc comment.
  ///
  /// Reuses `saveTechnicianSignature`'s save/render tail (`_SignatureBlock._captureSig` makes the
  /// same call), but with `stampCapture: false`: nothing was actually signed here — no draw, no
  /// tap, no signing act at all — so this deliberately does NOT claim a live GPS position or "just
  /// captured" timestamp the way a real capture does. Doing so would stamp a pre-filled signature
  /// as if it had just been signed at the device's current location, undermining the exact
  /// authenticity purpose GPS + timestamp exist for. See `ReportEditorNotifier
  /// .saveTechnicianSignature`'s own doc comment on `stampCapture`.
  ///
  /// Never blocks the editor from opening: a fetch failure or a missing saved signature both
  /// no-op silently (see `UserSignatureApiClient.fetchSavedSignatureContent`'s own "never blocks"
  /// contract).
  Future<void> _maybePrefillTechnicianSignature() async {
    final notifier = ref.read(reportEditorProvider(widget.reportId).notifier);
    await notifier.ready;
    if (!mounted) return;
    if (_technicianPrefillBlocked()) return;

    final bytes = await ref.read(userSignatureApiClientProvider).fetchSavedSignatureContent();
    if (bytes == null || !mounted) return;
    // Re-check after the fetch: a resumed draft's hydration, a manual capture, or a deliberate
    // Cancella could all have completed while the network call was in flight.
    if (_technicianPrefillBlocked()) return;

    final dir = await getApplicationDocumentsDirectory();
    final id = 'sig-tecnico-${DateTime.now().millisecondsSinceEpoch}';
    final file = File('${dir.path}/$id.png');
    await file.writeAsBytes(bytes);
    if (!mounted) return;

    await ref
        .read(reportEditorProvider(widget.reportId).notifier)
        .saveTechnicianSignature(
          allegatoId: id,
          bytes: bytes,
          localPath: file.path,
          stampCapture: false,
        );
  }

  bool _technicianPrefillBlocked() {
    final state = ref.read(reportEditorProvider(widget.reportId));
    return state.technicianSignatureAllegatoId != null ||
        state.technicianSignaturePrefillSuppressed;
  }

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
    final validation = state.validation;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.base,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
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
            stream: _draftStream,
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
                    // AppButton has no gradientColors escape hatch (VetroButton's own — the old
                    // fixed stopLight/stopDark pair had no themed equivalent to move to). This
                    // resubmit action is exactly the case AppButton's own `danger` variant exists
                    // for — a destructive/error-recovery affordance — and its fill/fg already read
                    // through `context.colors.redSoft`/`context.colors.red` rather than a fixed
                    // hex pair, so it carries the same "this failed, look here" language across
                    // both themes instead of one gradient tuned for light mode only.
                    AppButton.danger(
                      label: 'Riprova invio',
                      icon: const Icon(LucideIcons.refreshCw),
                      onPressed: _submitting ? null : _onInvia,
                      isLoading: _submitting,
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
      padding: const EdgeInsets.all(AppSpacing.base),
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
              padding: const EdgeInsets.only(top: AppSpacing.xs),
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
      padding: const EdgeInsets.all(AppSpacing.base),
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

class _SignatureBlock extends ConsumerStatefulWidget {
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
  ConsumerState<_SignatureBlock> createState() => _SignatureBlockState();
}

class _SignatureBlockState extends ConsumerState<_SignatureBlock> {
  /// True from the moment the capture dialog hands back bytes (user tapped Conferma) until the
  /// notifier's `saveCustomerSignature`/`saveTechnicianSignature` call resolves.
  ///
  /// That save includes an up-to-10s GPS fix attempt on a real device with permission already
  /// granted (`LocationService.getCurrentPosition`'s own `timeLimit`) — before this flag existed,
  /// the block showed nothing for that whole window: the technician/customer had just signed and
  /// tapped Conferma, and the screen visibly did not react. Drives the loading UI below (mirrors
  /// `PunchNotifier`'s `AsyncLoading()` during the same kind of wait) and disables re-tapping
  /// "Acquisisci firma" mid-capture, so a second capture can't start with a different local
  /// allegato id before the first save lands.
  bool _capturing = false;

  @override
  Widget build(BuildContext context) {
    final captured = widget.localPath != null && widget.allegatoId != null;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (captured) ...[
            // Show captured image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(widget.localPath!),
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
                  onPressed: () => _clearSig(),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: Text('Cancella', style: TextStyle(color: context.colors.red)),
                ),
              ],
            ),
          ] else ...[
            // Dashed empty area — shows a spinner in place of the label while a capture's save is
            // in flight (see `_capturing`'s own doc comment).
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: context.colors.bg2,
                border: Border.all(color: context.colors.borderStrong, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: _capturing
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(context.colors.inkMuted),
                        ),
                      )
                    : Text(
                        'Firma ${widget.label} non acquisita',
                        style: TextStyle(color: context.colors.inkMuted, fontSize: 13),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            AppButton(
              label: _capturing ? 'Acquisizione in corso...' : 'Acquisisci firma ${widget.label}',
              icon: _capturing ? null : const Icon(LucideIcons.penTool),
              isLoading: _capturing,
              onPressed: _capturing ? null : () => _captureSig(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _captureSig(BuildContext context) async {
    final mode = await showDialog<_SigMode>(
      context: context,
      builder: (_) => const _SigModeDialog(),
    );
    if (mode == null || !context.mounted) return;

    final bytes = await showDialog<Uint8List?>(
      context: context,
      builder: (_) => mode == _SigMode.draw ? const _SigDialog() : const _TypedSigDialog(),
    );
    if (bytes == null || bytes.isEmpty) return;

    setState(() => _capturing = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final id =
          '${widget.isCustomer ? 'sig-cliente' : 'sig-tecnico'}-'
          '${DateTime.now().millisecondsSinceEpoch}';
      final file = File('${dir.path}/$id.png');
      await file.writeAsBytes(bytes);

      final notifier = ref.read(reportEditorProvider(widget.reportId).notifier);
      if (widget.isCustomer) {
        await notifier.saveCustomerSignature(allegatoId: id, bytes: bytes, localPath: file.path);
      } else {
        await notifier.saveTechnicianSignature(
          allegatoId: id,
          bytes: bytes,
          localPath: file.path,
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }

    // Reuse only makes sense for an actual drawn technician signature image — a typed one is a
    // rendered name-and-checkmark stand-in, not a signature worth carrying forward to the next
    // rapportino. Deliberately outside the `_capturing` window above: the signature is already
    // saved and rendered as captured at this point, so this optional follow-up prompt must not
    // hold up that feedback.
    if (!widget.isCustomer && mode == _SigMode.draw && context.mounted) {
      await _offerToSaveForReuse(context, bytes);
    }
  }

  /// Asks whether to save this (drawn) technician signature for reuse on future rapportini, and
  /// uploads it on "Sì".
  ///
  /// The upload itself is fire-and-forget — a slow or failed upload must not hold up this
  /// rapportino's own editor — but unlike the GPS/pre-fill "never blocks" paths, this is a
  /// deliberate technician action ("save this for next time"), so a failure is surfaced with a
  /// SnackBar rather than swallowed silently.
  Future<void> _offerToSaveForReuse(BuildContext context, Uint8List bytes) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Salva firma'),
        content: const Text('Salva questa firma per la prossima volta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sì')),
        ],
      ),
    );
    if (confirm != true) return;

    final messenger = context.mounted ? ScaffoldMessenger.maybeOf(context) : null;
    unawaited(_uploadForReuse(bytes, messenger));
  }

  Future<void> _uploadForReuse(Uint8List bytes, ScaffoldMessengerState? messenger) async {
    try {
      await ref.read(userSignatureApiClientProvider).uploadSignature(bytes);
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Impossibile salvare la firma per il riutilizzo.')),
      );
    }
  }

  Future<void> _clearSig() async {
    final notifier = ref.read(reportEditorProvider(widget.reportId).notifier);
    if (widget.isCustomer) {
      await notifier.clearCustomerSignature();
    } else {
      await notifier.clearTechnicianSignature();
    }
  }
}

// ── Signature mode choice ────────────────────────────────────────────────────

enum _SigMode { draw, typed }

/// Asked before either capture flow opens: draw on the pad, or type a name and accept.
///
/// A plain `AlertDialog`/`SimpleDialogOption` pair, matching `confirm_delete_dialog.dart`'s own
/// `showDialog<T>` + stock Material dialog convention rather than inventing a bespoke chooser.
class _SigModeDialog extends StatelessWidget {
  const _SigModeDialog();

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Come vuoi firmare?'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _SigMode.draw),
          child: Row(
            children: [
              Icon(LucideIcons.penTool, color: context.colors.ink, size: 20),
              const SizedBox(width: 12),
              Text('Disegna', style: TextStyle(color: context.colors.ink, fontSize: 15)),
            ],
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _SigMode.typed),
          child: Row(
            children: [
              Icon(LucideIcons.pencil, color: context.colors.ink, size: 20),
              const SizedBox(width: 12),
              Text('Digita', style: TextStyle(color: context.colors.ink, fontSize: 15)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Typed signature dialog ───────────────────────────────────────────────────

/// The "Digita" alternative to `_SigDialog`'s drawing pad: a full name plus an explicit
/// confirmation checkbox, rendered to a PNG that stands in for a drawn stroke.
///
/// No backend concept of "typed vs drawn" exists — this renders an image client-side and hands
/// it back through the exact same `showDialog<Uint8List?>` contract `_SigDialog` uses, so
/// `_SignatureBlock._captureSig`'s file-write-and-save tail needs zero changes for this mode.
class _TypedSigDialog extends StatefulWidget {
  const _TypedSigDialog();

  @override
  State<_TypedSigDialog> createState() => _TypedSigDialogState();
}

class _TypedSigDialogState extends State<_TypedSigDialog> {
  final _nameCtrl = TextEditingController();
  bool _confirmed = false;
  bool _rendering = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _canConfirm => _nameCtrl.text.trim().isNotEmpty && _confirmed && !_rendering;

  Future<void> _onConfirm() async {
    setState(() => _rendering = true);
    final bytes = await _renderTypedSignature(_nameCtrl.text.trim());
    if (mounted) Navigator.pop(context, bytes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Firma digitale'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: 'Nome e cognome',
            hint: 'Mario Rossi',
            controller: _nameCtrl,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Confermo l\'accettazione',
              style: TextStyle(color: context.colors.ink, fontSize: 14),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _rendering ? null : () => Navigator.pop(context),
          child: Text('Annulla', style: TextStyle(color: context.colors.inkMuted)),
        ),
        TextButton(
          onPressed: _canConfirm ? _onConfirm : null,
          child: _rendering
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.Y),
                )
              : Text(
                  'Conferma',
                  style: TextStyle(color: AppColors.Y, fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}

/// Renders `name` + a checkmark + the current timestamp to an offscreen canvas and returns it as
/// PNG bytes.
///
/// 800x400 (2:1) is a deliberate pick, not a measured match: `_SigDialog`'s own PNG dimensions
/// come from `SignatureController`'s export, which sizes to whatever the drawing widget's runtime
/// layout happens to be on a full-screen landscape dialog — there's no single fixed constant to
/// replicate. 2:1 lands in the same ballpark as that landscape aspect ratio, and 800px wide is
/// comfortably sharp for the ~120px-tall preview `_SignatureBlock` renders it at.
Future<Uint8List> _renderTypedSignature(String name) async {
  const width = 800.0;
  const height = 400.0;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
  canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);

  final now = DateTime.now();
  final timestamp =
      '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/'
      '${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

  final painter = TextPainter(
    text: TextSpan(
      children: [
        TextSpan(
          text: '$name  ✓\n',
          style: const TextStyle(color: Colors.black, fontSize: 48, fontWeight: FontWeight.w600),
        ),
        TextSpan(
          text: timestamp,
          style: TextStyle(color: Colors.black.withValues(alpha: 0.7), fontSize: 24),
        ),
      ],
    ),
    textDirection: TextDirection.ltr,
  );
  painter.layout(maxWidth: width - 80);
  painter.paint(canvas, Offset(40, (height - painter.height) / 2));

  final picture = recorder.endRecording();
  final image = await picture.toImage(width.toInt(), height.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
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
    // A signature is the one input on this whole screen where the phone's short edge is a real
    // constraint — landscape gives noticeably more width to write in. Nothing else in the app
    // sets a preferred orientation (grep turns up nothing), so there's no existing lock to
    // respect here; this dialog claims landscape for itself and hands orientation back to
    // "whatever the OS wants" — not a portrait lock — the moment it closes, in dispose below.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Fixed ink, not `context.colors.ink` — that used to throw: `Theme.of(context)` (what
    // `context.colors` resolves through) establishes an InheritedWidget dependency, and Flutter
    // asserts against doing that before initState() completes ("dependOnInheritedWidgetOfExact
    // Type<_InheritedTheme>() ... was called before _SigDialogState.initState() completed").
    // Reproduced with a real drawn stroke in step_riepilogo_signature_test.dart — every capture
    // attempt hit this before a single pixel could be signed.
    //
    // A fixed value is also the more consistent choice, not just the fix: this dialog's AppBar is
    // already fixed CHARCOAL/onDark regardless of theme, for the exact same "captures a signature,
    // must not go near-invisible if the ink also flipped" reasoning (see this class's own AppBar
    // comment) — the pen should not have been the one themed thing on an otherwise fixed surface.
    _ctrl = SignatureController(
      penStrokeWidth: 3,
      penColor: AppColors.DARK,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    // Restores the app's actual default — every orientation, sensor-driven — not portrait. An
    // empty list is Flutter's own idiom for "no preference, allow all"; a hardcoded portraitUp
    // here would be a second, unrelated behavior change smuggled into a signature-capture fix.
    SystemChrome.setPreferredOrientations([]);
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
          AppBar(
            backgroundColor: context.colors.bg1,
            foregroundColor: context.colors.ink,
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
                child: Text(
                  'Conferma',
                  style: TextStyle(color: AppColors.Y, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.all(AppSpacing.md),
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
