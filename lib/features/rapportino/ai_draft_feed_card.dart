// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ai/ai_api_client.dart';
import '../../presentation/providers/report_editor_providers.dart';
import 'ai_draft_feed.dart';

/// Shown in the ordinary editor when this rapportino is fed by a live AI draft (Task 12).
///
/// What the technician changes here counts as CONFIRMED: it is sent to the server as confirmed
/// edits ("Sincronizza modifiche", and automatically when they leave the editor), so a later voice
/// update that disagrees is flagged instead of overwriting it. "Aggiorna dalla bozza" pulls the
/// latest server draft into the report, again without touching what was changed by hand.
///
/// Renders nothing for a rapportino without a live draft.
class AiDraftFeedCard extends ConsumerStatefulWidget {
  const AiDraftFeedCard({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<AiDraftFeedCard> createState() => _AiDraftFeedCardState();
}

class _AiDraftFeedCardState extends ConsumerState<AiDraftFeedCard> {
  String? _sessionId;
  bool _busy = false;

  /// Shown persistently, not only as a toast: a blocked sync and the edits that cannot reach the
  /// server stay on the card until they are resolved.
  AiFeedStatus _status = const AiFeedStatus();
  late final AiEditSyncer _syncer;
  late final AiDraftFeed _feed;
  late final AiApiClient _client;

  @override
  void initState() {
    super.initState();
    // Read once: dispose() must not touch `ref`.
    _syncer = ref.read(aiEditSyncerProvider);
    _feed = ref.read(aiDraftFeedProvider);
    _client = ref.read(aiApiClientProvider);
    unawaited(_load());
  }

  Future<void> _load() async {
    String? id;
    try {
      id = await _feed.store.sessionForReport(widget.reportId);
    } catch (_) {
      id = null; // no readable feed state: not an AI-fed rapportino
    }
    if (mounted && id != null) setState(() => _sessionId = id);
    await _loadStatus();
  }

  Future<void> _loadStatus() async {
    final id = _sessionId;
    if (id == null) return;
    try {
      final status = await _feed.status(id);
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // Unreadable state: nothing to show.
    }
  }

  @override
  void dispose() {
    // Leaving the editor delivers the hand edits (edits-only: no model, no charge). Best effort:
    // an unacknowledged batch is persisted and resent, same key, by the next sync or turn.
    final id = _sessionId;
    if (id != null) {
      unawaited(_leave(id));
    }
    super.dispose();
  }

  Future<void> _leave(String id) async {
    try {
      // Submitted (or queued) from this editor: the draft behind it was used. Release the session
      // so a later visit never re-applies this visit's lines (best effort; the copilot's resume
      // check covers a release that did not get through). Nothing is written to the report.
      if (await _feed.reportWasSubmitted(widget.reportId)) {
        await releaseAiSessionForSubmittedReport(
          store: _feed.store,
          client: _client,
          reportId: widget.reportId,
        );
        return;
      }
      final d = await _syncer.sync(id);
      if (d != null) await _feed.apply(id, d);
    } catch (_) {}
  }

  Future<void> _run(Future<String> Function(String sessionId) op) async {
    final id = _sessionId;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      final message = await op(id);
      // The editor hydrates once: re-read the rows the apply may have written.
      ref.invalidate(reportEditorProvider(widget.reportId));
      if (mounted) showAppToast(context, message: message, tone: ToastTone.success);
    } on AiEditSyncBlockedException catch (e) {
      if (mounted) showAppToast(context, message: e.message, tone: ToastTone.warning);
    } catch (e) {
      if (mounted) showAppToast(context, message: e.toString(), tone: ToastTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _loadStatus();
    }
  }

  Future<String> _sync(String id) async {
    final draft = await _syncer.sync(id);
    if (draft == null) return 'Nessuna modifica da sincronizzare.';
    await _feed.apply(id, draft);
    return 'Modifiche sincronizzate con la bozza AI.';
  }

  Future<String> _refresh(String id) async {
    // Hand edits first, so the draft that comes back already holds them.
    await _syncer.sync(id);
    final detail = await ref.read(aiApiClientProvider).getConversation(id);
    await _feed.apply(id, detail.draft);
    return 'Rapporto di intervento aggiornato dalla bozza AI.';
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionId == null) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.penTool, size: 18, color: c.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Collegato alla bozza AI',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink),
                      ),
                      Text(
                        'Quello che modifichi qui vale come confermato: l\'AI non lo sovrascrive. '
                        'Le voci solo pianificate restano fuori finché non le accetti.',
                        style: TextStyle(fontSize: 11, color: c.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_status.blocked) ...[
              const SizedBox(height: 8),
              Text(
                _status.blockedMessage,
                key: const ValueKey('ai-feed-blocked'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.red),
              ),
            ],
            if (_status.unsendable.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _status.notice,
                key: const ValueKey('ai-feed-unsendable'),
                style: TextStyle(fontSize: 12, color: c.red),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  label: 'Sincronizza modifiche',
                  size: AppButtonSize.sm,
                  fullWidth: false,
                  isLoading: _busy,
                  onPressed: _busy || _status.blocked ? null : () => _run(_sync),
                ),
                AppButton.secondary(
                  label: 'Aggiorna dalla bozza',
                  size: AppButtonSize.sm,
                  fullWidth: false,
                  onPressed: _busy ? null : () => _run(_refresh),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
