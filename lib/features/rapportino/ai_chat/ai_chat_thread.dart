// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

import 'chat_message.dart';

/// The Descrivi conversation: operator bubbles (right, audio marked), assistant bubbles (left),
/// a "thinking" bubble while a turn runs, and the retry action on the one unsent message.
///
/// The thread is what the server already stores (`GET /api/ai/conversations/{id}`) plus the
/// optimistic operator message the screen adds while the turn is in flight. It scrolls to the end
/// whenever a message arrives, honouring reduced motion.
class AiChatThread extends StatefulWidget {
  const AiChatThread({
    super.key,
    required this.messages,
    required this.thinking,
    required this.thinkingLabel,
    this.speakingLastReply = false,
    this.onSpeakLastReply,
    this.failedMessageId,
    this.onRetryFailed,
  });

  final List<ChatMessage> messages;
  final bool thinking;
  final String thinkingLabel;
  final bool speakingLastReply;
  final VoidCallback? onSpeakLastReply;

  /// The operator message the server did not accept; its retry lives on that bubble.
  final String? failedMessageId;
  final VoidCallback? onRetryFailed;

  @override
  State<AiChatThread> createState() => _AiChatThreadState();
}

class _AiChatThreadState extends State<AiChatThread> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant AiChatThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.length != widget.messages.length ||
        oldWidget.thinking != widget.thinking) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  void _scrollToEnd() {
    if (!mounted || !_controller.hasClients) return;
    final target = _controller.position.maxScrollExtent;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.jumpTo(target);
    } else {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lastAssistantId = widget.messages
        .lastWhereOrNull((m) => m.role == ChatRole.assistant)
        ?.id;

    return ListView(
      key: const ValueKey('ai-chat-thread'),
      controller: _controller,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.sm,
      ),
      children: [
        for (final m in widget.messages)
          _Bubble(
            key: ValueKey('ai-msg-${m.id}'),
            message: m,
            failed: m.id == widget.failedMessageId,
            canSpeak: m.id == lastAssistantId && widget.onSpeakLastReply != null,
            speaking: widget.speakingLastReply,
            onSpeak: widget.onSpeakLastReply,
            onRetry: widget.onRetryFailed,
          ),
        if (widget.thinking) _ThinkingBubble(label: widget.thinkingLabel),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.failed,
    required this.canSpeak,
    required this.speaking,
    this.onSpeak,
    this.onRetry,
  });

  final ChatMessage message;
  final bool failed;
  final bool canSpeak;
  final bool speaking;
  final VoidCallback? onSpeak;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final operator = message.role == ChatRole.operator;

    return Semantics(
      label: operator ? 'Tu: ${message.text}' : 'Assistente: ${message.text}',
      child: Align(
        alignment: operator ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: operator ? colors.surfaceInverse : colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: failed ? colors.red : colors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.source == ChatSource.voice) ...[
                    Icon(LucideIcons.mic, size: 12, color: operator ? colors.inkInverse : colors.inkMuted),
                    const SizedBox(width: 4),
                  ],
                  if (canSpeak)
                    IconButton(
                      key: const ValueKey('ai-speak-last'),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      tooltip: speaking ? 'Interrompi la lettura' : 'Ascolta la risposta',
                      icon: Icon(
                        speaking ? LucideIcons.volumeX : LucideIcons.volume2,
                        size: 14,
                        color: colors.inkMuted,
                      ),
                      onPressed: onSpeak,
                    ),
                ],
              ),
              Text(
                message.text,
                style: TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 14,
                  height: 1.35,
                  color: operator ? colors.inkInverse : colors.ink,
                ),
              ),
              if (failed && onRetry != null) ...[
                const SizedBox(height: 6),
                TextButton(
                  key: const ValueKey('ai-msg-retry'),
                  onPressed: onRetry,
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: const Text('Riprova'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey('ai-thinking'),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: colors.amber),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontFamily: 'IBM Plex Mono', fontSize: 11, color: colors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

extension _LastWhereOrNull<T> on Iterable<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    T? found;
    for (final value in this) {
      if (test(value)) found = value;
    }
    return found;
  }
}
