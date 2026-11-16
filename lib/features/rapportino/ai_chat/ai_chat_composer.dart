// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// The input row under the chat: microphone, optional text field, send.
///
/// Voice remains the primary path (ADR-0023: the recording is the model's input); the text field
/// is the same alternate the wizard offered, kept for noisy sites and no-signal dictation. The send
/// action is enabled only with text, exactly like the old footer's "Genera il rapporto".
class AiChatComposer extends StatefulWidget {
  const AiChatComposer({
    super.key,
    required this.controller,
    required this.recording,
    required this.busy,
    required this.writing,
    required this.micEnabled,
    required this.onMic,
    required this.onToggleWriting,
    required this.onSend,
    required this.onTextChanged,
  });

  final TextEditingController controller;
  final bool recording;
  final bool busy;
  final bool writing;
  final bool micEnabled;
  final VoidCallback onMic;
  final VoidCallback onToggleWriting;
  final VoidCallback onSend;
  final VoidCallback onTextChanged;

  @override
  State<AiChatComposer> createState() => _AiChatComposerState();
}

class _AiChatComposerState extends State<AiChatComposer> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasText = widget.controller.text.trim().isNotEmpty;
    final showField = widget.writing || hasText;

    return Container(
      key: const ValueKey('ai-chat-composer'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.bg1,
        border: Border(top: BorderSide(color: colors.borderLight)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _RoundAction(
                key: const ValueKey('ai-chat-mic'),
                icon: widget.recording ? LucideIcons.square : LucideIcons.mic,
                label: widget.recording ? 'Ferma la registrazione' : 'Registra un messaggio',
                color: colors.red,
                // While recording the same control stops it — `_toggleMic` owns that decision.
                onTap: widget.busy || !widget.micEnabled ? null : widget.onMic,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: showField
                    ? TextField(
                        key: const ValueKey('ai-description-field'),
                        controller: widget.controller,
                        enabled: !widget.busy,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Scrivi cosa hai fatto…',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                          ),
                        ),
                        style: TextStyle(
                          fontFamily: 'Archivo',
                          fontSize: 14,
                          height: 1.35,
                          color: colors.ink,
                        ),
                        onChanged: (_) {
                          setState(() {});
                          widget.onTextChanged();
                        },
                      )
                    : GestureDetector(
                        key: const ValueKey('ai-chat-hint'),
                        onTap: widget.onToggleWriting,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            widget.recording
                                ? 'In ascolto… tocca il quadrato per fermare.'
                                : 'Tocca il microfono per parlare, o scrivi.',
                            style: TextStyle(fontSize: 12, color: colors.inkMuted),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _RoundAction(
                key: const ValueKey('ai-chat-send'),
                icon: LucideIcons.send,
                label: 'Invia il messaggio',
                color: colors.red,
                onTap: hasText && !widget.busy && !widget.recording ? widget.onSend : null,
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('ai-toggle-writing'),
              onPressed: widget.recording ? null : widget.onToggleWriting,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: Text(
                widget.writing ? 'Descrivi a voce' : 'Preferisci scrivere?',
                style: TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.red,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? color : colors.bg3,
          ),
          child: Icon(icon, size: 20, color: enabled ? Colors.white : colors.inkDisabled),
        ),
      ),
    );
  }
}
