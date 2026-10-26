// dart format width=100
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signature/signature.dart';

import '../../../core/icons/app_lucide_icons.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/sync/submission_queue_watcher.dart';
import '../../../presentation/providers/report_editor_providers.dart';
import 'ai_card.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 3 of the AI report flow: "Firma del cliente".
//
// Its own route, not a third step of the flow screen: by the time it opens, Confirm has already
// resolved the AI conversation and written a real local draft, so this screen works on a report id
// like every other signing surface in the app — the same `reportEditorProvider` notifier, the same
// `saveCustomerSignature`, the same `SubmissionQueue`. Nothing AI-specific is left by the time the
// customer signs.
//
// The report stays a draft until this screen's one button sends it: "Firma e invia all'ufficio" is
// the same enqueue + forced flush the editor's own submit uses.
// ══════════════════════════════════════════════════════════════════════════════

class AiSignScreen extends ConsumerStatefulWidget {
  const AiSignScreen({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<AiSignScreen> createState() => _AiSignScreenState();
}

class _AiSignScreenState extends ConsumerState<AiSignScreen> {
  bool _capturing = false;
  bool _sending = false;
  String? _error;

  Future<void> _capture(ReportEditorNotifier notifier) async {
    final bytes = await showDialog<Uint8List?>(
      context: context,
      builder: (_) => const _FirmaDialog(),
    );
    if (bytes == null || bytes.isEmpty || !mounted) return;

    setState(() => _capturing = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final id = 'sig-cliente-${DateTime.now().millisecondsSinceEpoch}';
      final file = File('${dir.path}/$id.png');
      await file.writeAsBytes(bytes);
      await notifier.saveCustomerSignature(allegatoId: id, bytes: bytes, localPath: file.path);
    } catch (e) {
      if (mounted) {
        setState(() => _error = humanErrorMessage(e, azione: 'salvare la firma'));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _send(ReportEditorState state) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final queue = ref.read(realSubmissionQueueProvider);
    try {
      await queue.enqueue(widget.reportId);
      await queue.processAll(force: true);
      if (!mounted) return;
      showAppToast(context, message: 'Rapporto inviato all\'ufficio', tone: ToastTone.success);
      final ticketId = state.ticketId;
      if (ticketId != null && ticketId.isNotEmpty) {
        context.go(AppRoutes.ticketDetailPath(ticketId));
      } else {
        context.go(AppRoutes.rapportiniView(widget.reportId));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = humanErrorMessage(e, azione: 'inviare il rapporto di intervento'));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportEditorProvider(widget.reportId));
    final notifier = ref.read(reportEditorProvider(widget.reportId).notifier);
    final signed = state.customerSignatureAllegatoId != null;
    final hours = state.staffRows
        .map((r) => r.hoursWorked)
        .whereType<double>()
        .fold<double>(0, (a, b) => a + b);

    return PopScope(
      // Leaving mid-flow must not silently drop the report: it stays a draft on the phone either
      // way, but the technician should know that is what happened.
      canPop: !_sending,
      child: Scaffold(
        backgroundColor: context.colors.bg2,
        body: SafeArea(
          child: Column(
            children: [
              ScreenHeader(
                title: 'Firma del cliente',
                subtitle: state.title.isEmpty ? null : state.title,
                showBack: true,
                onBack: () => context.pop(),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pagePadding,
                    AppSpacing.base,
                    AppSpacing.pagePadding,
                    AppSpacing.base,
                  ),
                  children: [
                    // ── Riepilogo ────────────────────────────────────────────────
                    AiCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AiLabel('Riepilogo'),
                          AiKvRow(
                            first: true,
                            label: 'Lavoro svolto',
                            value: state.title.isEmpty ? '—' : state.title,
                          ),
                          AiKvRow(
                            label: 'Materiali',
                            value: state.materialeRows.isEmpty
                                ? 'nessuno'
                                : '${state.materialeRows.length} '
                                      '${state.materialeRows.length == 1 ? 'voce' : 'voci'}',
                          ),
                          AiKvRow(
                            label: 'Ore',
                            value: hours > 0
                                ? '${hours == hours.roundToDouble() ? hours.round() : hours.toString().replaceAll('.', ',')} h'
                                : '—',
                          ),
                        ],
                      ),
                    ),
                    const AiCardGap(),

                    // ── Firma ────────────────────────────────────────────────────
                    AiCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AiLabel('Firma qui'),
                          const SizedBox(height: 8),
                          if (signed && state.customerSignatureLocalPath != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.file(
                                File(state.customerSignatureLocalPath!),
                                height: 140,
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, e, _) => Icon(
                                  LucideIcons.imageOff,
                                  color: context.colors.inkMuted,
                                  size: 40,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                key: const ValueKey('ai-sign-clear'),
                                onPressed: _capturing || _sending
                                    ? null
                                    : () => notifier.clearCustomerSignature(),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(44, 44),
                                ),
                                child: Text(
                                  'Cancella firma',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: context.colors.red,
                                  ),
                                ),
                              ),
                            ),
                          ] else
                            GestureDetector(
                              key: const ValueKey('ai-sign-capture'),
                              onTap: _capturing || _sending ? null : () => _capture(notifier),
                              child: Container(
                                height: 140,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: context.colors.borderStrong,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: Center(
                                  child: _capturing
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : AiHelper('Fai firmare il cliente con il dito'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const AiCardGap(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: context.colors.red.withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontFamily: 'Archivo',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            color: context.colors.red,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.sm,
                  AppSpacing.pagePadding,
                  AppSpacing.base,
                ),
                child: AppButton(
                  label: _sending ? 'Invio in corso…' : 'Firma e invia all\'ufficio',
                  isLoading: _sending,
                  onPressed: !signed || _sending || _capturing ? null : () => _send(state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen signature pad, landscape, dismissed with an X.
///
/// Deliberately the same capture surface the editor's own signature block uses (pen width, ink and
/// white export background), including the orientation claim — a signature is the one input on this
/// phone where the short edge is a real constraint, and a customer signing in the back of a van
/// should get the same pad every time.
class _FirmaDialog extends StatefulWidget {
  const _FirmaDialog();

  @override
  State<_FirmaDialog> createState() => _FirmaDialogState();
}

class _FirmaDialogState extends State<_FirmaDialog> {
  late final SignatureController _ctrl;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Fixed ink, not `context.colors.ink`: `Theme.of(context)` must not be read before initState
    // completes, and this pad must not go near-invisible under the dark theme either.
    _ctrl = SignatureController(
      penStrokeWidth: 3,
      penColor: AppColors.DARK,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    // Empty list = "no preference", the app's real default — not a portrait lock.
    SystemChrome.setPreferredOrientations([]);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Column(
        children: [
          AppBar(
            backgroundColor: context.colors.bg1,
            foregroundColor: context.colors.ink,
            title: const Text('Firma del cliente'),
            leading: IconButton(
              icon: const Icon(LucideIcons.x),
              tooltip: 'Chiudi',
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              TextButton(
                onPressed: () => _ctrl.clear(),
                child: Text('Cancella', style: TextStyle(color: context.colors.inkMuted)),
              ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: TextButton(
                  onPressed: () async {
                    if (_ctrl.isEmpty) {
                      Navigator.pop(context);
                      return;
                    }
                    final bytes = await _ctrl.toPngBytes();
                    if (context.mounted) Navigator.pop(context, bytes);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.Y,
                    foregroundColor: context.colors.brandOn,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Conferma', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              'Firma nell\'area sottostante',
              style: TextStyle(color: context.colors.inkMuted),
            ),
          ),
          Expanded(child: Signature(controller: _ctrl, backgroundColor: context.colors.bg1)),
        ],
      ),
    );
  }
}
