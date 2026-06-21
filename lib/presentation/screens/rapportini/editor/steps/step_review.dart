// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../data/local/app_database.dart';
import '../../../../../data/sync/draft_submission_state.dart';
import '../../../../../data/sync/submission_queue_watcher.dart';
import '../../../../../domain/reports/draft_validation.dart';
import '../../../../providers/report_editor_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 7 — Review / Riepilogo
//
// Summary of all filled data + local validation panel.
// Marks the draft "pronto per invio" when all rules pass.
// Actual submission is M5.
// ══════════════════════════════════════════════════════════════════════════════

class StepReview extends ConsumerStatefulWidget {
  const StepReview({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<StepReview> createState() => _StepReviewState();
}

class _StepReviewState extends ConsumerState<StepReview> {
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
      setState(() => _submitError = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reportEditorProvider(widget.reportId));
    final validation = state.validation;

    // Watch live draft for submission state
    final repo = ref.watch(draftReportRepositoryProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Validation panel
          _ValidationPanel(validation: validation),
          const SizedBox(height: 20),

          // Summary sections
          _ReviewSection(
            title: 'Dati Generali',
            items: [
              _ReviewItem('Titolo', state.title.isEmpty ? '—' : state.title),
              _ReviewItem(
                'Cliente',
                state.customerId ?? state.customerFreeText ?? '—',
              ),
              _ReviewItem('Indirizzo', state.workAddress ?? '—'),
              if (state.ticketId != null)
                _ReviewItem('Ticket', state.ticketId!),
              if (state.ticketFreeText != null)
                _ReviewItem('Ticket (libero)', state.ticketFreeText!),
              if (state.cantiereId != null)
                _ReviewItem('Cantiere', state.cantiereId!),
              if (state.cantiereFreeText != null)
                _ReviewItem('Cantiere (libero)', state.cantiereFreeText!),
              if (state.gpsLatitude != null)
                _ReviewItem(
                  'GPS',
                  '${state.gpsLatitude!.toStringAsFixed(6)}, '
                      '${state.gpsLongitude!.toStringAsFixed(6)}',
                ),
            ],
          ),
          const SizedBox(height: 12),

          _ReviewSection(
            title: 'Staff (${state.staffRows.length} tecnici)',
            items: state.staffRows
                .map(
                  (s) => _ReviewItem(
                    s.displayName.isNotEmpty ? s.displayName : s.userId,
                    '${s.effectiveHours.toStringAsFixed(1)}h · ${s.kmTraveled.toStringAsFixed(0)} km',
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),

          _ReviewSection(
            title: state.materialiNotRequired
                ? 'Materiali (nessuno utilizzato)'
                : 'Materiali (${state.materialeRows.length})',
            items: state.materialiNotRequired
                ? [const _ReviewItem('Flag', 'Nessun materiale utilizzato')]
                : state.materialeRows
                    .map(
                      (m) => _ReviewItem(
                        m.displayName,
                        '${m.quantity} ${m.unitOfMeasure ?? ''}',
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 12),

          _ReviewSection(
            title: 'Controlli (${state.controlloRows.length})',
            items: state.controlloRows
                .map(
                  (c) => _ReviewItem(
                    c.controlId,
                    c.stringValue ??
                        (c.boolValue != null ? (c.boolValue! ? 'Sì' : 'No') : '—'),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),

          _ReviewSection(
            title: 'Firme',
            items: [
              _ReviewItem(
                'Firma cliente',
                state.customerSignatureAllegatoId != null
                    ? 'Acquisita'
                    : 'Mancante',
                isOk: state.customerSignatureAllegatoId != null,
              ),
              _ReviewItem(
                'Firma tecnico',
                state.technicianSignatureAllegatoId != null
                    ? 'Acquisita'
                    : 'Mancante',
                isOk: state.technicianSignatureAllegatoId != null,
              ),
            ],
          ),
          const SizedBox(height: 12),

          _ReviewSection(
            title:
                'Foto / Allegati (${state.allegatoRows.where((a) => !a.isSignature).length})',
            items: state.allegatoRows
                .where((a) => !a.isSignature)
                .map((a) => _ReviewItem(a.fileName, a.localPath))
                .toList(),
          ),

          const SizedBox(height: 24),

          // ── Submission state + Invia button ────────────────────────────────
          StreamBuilder<DraftReport?>(
            stream: repo.watchDraft(widget.reportId),
            builder: (context, snap) {
              final draft = snap.data;
              final subState = DraftSubmissionState.fromString(
                  draft?.submissionState ?? 'draft');

              if (subState == DraftSubmissionState.submitted) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    border: Border.all(color: Colors.green),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Rapportino inviato con successo.',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (subState == DraftSubmissionState.uploadingMedia ||
                  subState == DraftSubmissionState.submitting) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    border: Border.all(color: Colors.blue),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        subState == DraftSubmissionState.uploadingMedia
                            ? 'Caricamento media in corso...'
                            : 'Invio rapportino...',
                        style: const TextStyle(color: Colors.blue),
                      ),
                    ],
                  ),
                );
              }

              if (subState == DraftSubmissionState.failed) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Invio fallito',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red),
                              ),
                            ],
                          ),
                          if (draft?.submissionError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                draft!.submissionError!,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.red),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _submitting ? null : _onInvia,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Riprova invio'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                );
              }

              // draft or readyToSubmit
              if (validation.isValid) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        border: Border.all(color: Colors.green),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.green, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pronto per l\'invio',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'Il rapportino è completo e pronto per essere inviato.',
                                  style:
                                      TextStyle(color: Colors.green, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_submitError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _submitError!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ElevatedButton.icon(
                      onPressed: _submitting ? null : _onInvia,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send),
                      label: Text(_submitting ? 'Invio in corso...' : 'Invia'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                );
              }

              return const SizedBox.shrink();
            },
          ),

          const SizedBox(height: 24),
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
    if (validation.isValid) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        border: Border.all(color: Colors.amber[400]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.amber[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Da completare prima dell\'invio:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber[900],
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
                  Icon(Icons.circle, size: 6, color: Colors.amber[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      msg,
                      style: TextStyle(color: Colors.amber[900], fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Review section widgets ────────────────────────────────────────────────────

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.title, required this.items});

  final String title;
  final List<_ReviewItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
          const Divider(height: 1),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('—', style: TextStyle(color: Colors.grey)),
            )
          else
            for (final item in items) item,
        ],
      ),
    );
  }
}

class _ReviewItem extends StatelessWidget {
  const _ReviewItem(this.label, this.value, {this.isOk});

  final String label;
  final String value;
  final bool? isOk;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: isOk == false
                    ? Colors.red
                    : isOk == true
                        ? Colors.green
                        : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          if (isOk != null)
            Icon(
              isOk! ? Icons.check_circle : Icons.cancel,
              color: isOk! ? Colors.green : Colors.red,
              size: 16,
            ),
        ],
      ),
    );
  }
}
