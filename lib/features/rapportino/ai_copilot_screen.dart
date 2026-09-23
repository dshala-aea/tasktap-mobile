// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/dictation/dictate_button.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ai/ai_api_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// AiCopilotScreen — the multi-turn AI copilot (distinct from step_dettagli.dart's
// single-shot "Genera con AI" action).
//
// The operator talks (typed, or dictated on-device per ADR-0017 — text only, never uploaded
// audio), the assistant calls TaskTap tools to verify people/hours/materials/checklist items
// against real data, and a structured draft builds up as the conversation progresses. Confermare
// is blocked while any open item is Ambiguous/Conflict, mirroring the backend's own gate, and
// creates the Bozza via POST .../confirm (idempotency-keyed) before pushing into the ordinary
// editor for review.
//
// No voice-recording-and-upload flow here (unlike the web copilot's record/transcribe control):
// this app has no server-transcription dependency wired at all, by design (see AiApiClient's own
// "Transcription is deliberately absent" note) — dictation goes through DictateButton, on-device,
// straight into the text field, same as every other dictated field in this app.
// ══════════════════════════════════════════════════════════════════════════════

class _ChatMessage {
  const _ChatMessage({required this.isOperator, required this.text});
  final bool isOperator;
  final String text;
}

class AiCopilotScreen extends ConsumerStatefulWidget {
  const AiCopilotScreen({super.key, this.ticketId, this.cantiereId});

  final String? ticketId;
  final String? cantiereId;

  @override
  ConsumerState<AiCopilotScreen> createState() => _AiCopilotScreenState();
}

class _AiCopilotScreenState extends ConsumerState<AiCopilotScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <_ChatMessage>[];

  String? _sessionId;
  AiCopilotDraftDto _draft = AiCopilotDraftDto.empty;
  bool _starting = true;
  bool _sending = false;
  bool _confirming = false;
  String? _startError;
  String? _confirmKey;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _startError = null;
    });
    try {
      final session = await ref
          .read(aiApiClientProvider)
          .startConversation(ticketId: widget.ticketId, cantiereId: widget.cantiereId);
      if (!mounted) return;
      setState(() {
        _sessionId = session.sessionId;
        _starting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _startError = e.toString();
      });
    }
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    final sessionId = _sessionId;
    if (text.isEmpty || sessionId == null || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(isOperator: true, text: text));
      _sending = true;
      // A new turn moves the draft's Version on — any pending confirm key is now stale.
      _confirmKey = null;
    });
    _inputCtrl.clear();
    _scrollToEnd();

    try {
      final result = await ref.read(aiApiClientProvider).sendTurn(sessionId, text);
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(isOperator: false, text: result.assistantReplyText));
        _draft = result.draft;
        _sending = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showAppToast(context, message: e.toString(), tone: ToastTone.error);
    }
  }

  Future<void> _confirm() async {
    final sessionId = _sessionId;
    if (sessionId == null || _confirming) return;

    _confirmKey ??= const Uuid().v4();
    setState(() => _confirming = true);

    try {
      final result = await ref
          .read(aiApiClientProvider)
          .confirmConversation(sessionId, idempotencyKey: _confirmKey!);
      if (!mounted) return;
      showAppToast(context, message: 'Rapportino creato', tone: ToastTone.success);
      context.go(AppRoutes.rapportiniEditor(result.reportId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        // A stale-version 409 means the draft moved on since this key was minted — the next
        // attempt must not replay it.
        if (e is AiConversationException && e.isStaleVersionConflict) _confirmKey = null;
      });
      showAppToast(context, message: e.toString(), tone: ToastTone.error);
    }
  }

  Future<void> _abandon() async {
    final sessionId = _sessionId;
    if (sessionId != null) {
      unawaited(ref.read(aiApiClientProvider).abandonConversation(sessionId));
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final quota = ref.watch(aiQuotaProvider);
    final quotaExhausted = quota.valueOrNull?.exhausted ?? false;
    final blocked = _draft.hasBlockingOpenItems;
    final sessionReady = _sessionId != null;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_abandon());
      },
      child: Scaffold(
        backgroundColor: context.colors.bg2,
        body: SafeArea(
          child: Column(
            children: [
              ScreenHeader(
                title: 'Rapportino con AI Copilot',
                showBack: true,
                onBack: _abandon,
              ),
              if (_starting) const Expanded(child: Center(child: CircularProgressIndicator())),
              if (_startError != null)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.pagePadding),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_startError!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          AppButton.secondary(label: 'Riprova', onPressed: _start),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!_starting && _startError == null) ...[
                Expanded(child: _buildChat(context)),
                if (_draft.workers.isNotEmpty ||
                    _draft.materials.isNotEmpty ||
                    _draft.controlli.isNotEmpty ||
                    _draft.diagnosi != null ||
                    _draft.soluzione != null ||
                    _draft.customerSignoffText != null ||
                    _draft.openItems.isNotEmpty)
                  _buildDraftSummary(context),
                _buildInputRow(context, sessionReady, quotaExhausted),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.pagePadding,
                    AppSpacing.sm,
                    AppSpacing.pagePadding,
                    AppSpacing.base,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppButton.secondary(label: 'Annulla', onPressed: _abandon),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: _confirming ? 'Creazione…' : 'Conferma e crea rapportino',
                          onPressed: !sessionReady || _messages.isEmpty || blocked || _confirming
                              ? null
                              : _confirm,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChat(BuildContext context) {
    if (_messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Center(
          child: Text(
            'Racconta cosa hai fatto, a voce o per iscritto — il copilot verifica persone, ore, '
            'materiali e checklist con i dati reali di TaskTap prima di proporre una bozza.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.inkMuted),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pagePadding,
        vertical: AppSpacing.sm,
      ),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _messages.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Il copilot sta elaborando…',
                style: TextStyle(color: context.colors.inkMuted, fontSize: 12),
              ),
            ),
          );
        }
        final m = _messages[i];
        return Align(
          alignment: m.isOperator ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: m.isOperator ? AppColors.Y : context.colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              m.text,
              style: TextStyle(color: m.isOperator ? Colors.white : context.colors.ink),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDraftSummary(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderMedium),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_draft.diagnosi != null) _draftLine('Diagnosi', _draft.diagnosi!),
            if (_draft.soluzione != null) _draftLine('Soluzione', _draft.soluzione!),
            if (_draft.customerSignoffText != null)
              _draftLine('Accettazione cliente', _draft.customerSignoffText!),
            for (final w in _draft.workers)
              _draftRow(
                '${w.fullName.isEmpty ? '—' : w.fullName}${w.hours != null ? ' · ${w.hours}h' : ''}',
                w.state,
              ),
            for (final m in _draft.materials)
              _draftRow('${m.name.isEmpty ? '—' : m.name} × ${m.quantity}', m.state),
            for (final c in _draft.controlli) _draftRow(c.describe(), c.state),
            if (_draft.openItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${_draft.openItems.length} punti da chiarire'
                  '${_draft.hasBlockingOpenItems ? ' — risolvi prima di confermare' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _draft.hasBlockingOpenItems ? context.colors.red : context.colors.inkMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _draftLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    // Text.rich, not a bare RichText: it picks up the ambient DefaultTextStyle and — unlike
    // RichText — is what find.text/find.textContaining actually look at in widget tests.
    child: Text.rich(
      TextSpan(
        style: TextStyle(color: context.colors.ink, fontSize: 12),
        children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: value),
        ],
      ),
    ),
  );

  Widget _draftRow(String label, AiResolutionState state) {
    final Color bg;
    final Color fg;
    switch (state) {
      case AiResolutionState.resolvedBySystem:
      case AiResolutionState.operatorConfirmed:
        bg = context.colors.green.withAlpha(31);
        fg = context.colors.green;
      case AiResolutionState.ambiguous:
        bg = context.colors.amber.withAlpha(31);
        fg = context.colors.amber;
      case AiResolutionState.conflict:
        bg = context.colors.red.withAlpha(31);
        fg = context.colors.red;
      case AiResolutionState.unresolved:
        bg = context.colors.bg3;
        fg = context.colors.inkMuted;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          AppBadge(label: state.name, small: true, bgColor: bg, fgColor: fg),
        ],
      ),
    );
  }

  Widget _buildInputRow(BuildContext context, bool sessionReady, bool quotaExhausted) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        0,
      ),
      child: AppTextField.multiline(
        label: 'Scrivi cosa hai fatto…',
        controller: _inputCtrl,
        maxLines: 3,
        enabled: sessionReady && !quotaExhausted,
        onChanged: (_) {},
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DictateButton(controller: _inputCtrl, onChanged: (_) {}, explainWhenUnavailable: false),
            IconButton(
              icon: Icon(LucideIcons.send, size: 18, color: context.colors.ink),
              tooltip: 'Invia',
              onPressed: sessionReady && !quotaExhausted && !_sending ? _send : null,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
      ),
    );
  }
}
