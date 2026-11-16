// dart format width=100
import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// The input row under the chat: microphone, optional text field, send — with the recording and the
/// sending made visible rather than merely true.
///
/// Voice remains the primary path (ADR-0023: the recording is the model's input); the text field
/// is the same alternate the wizard offered, kept for noisy sites and no-signal dictation. The send
/// action is enabled only with text, exactly like the old footer's "Genera il rapporto".
///
/// Three states used to be indistinguishable from a dead button: a recording running (the mic just
/// turned into a square), a message on its way to the model (the send icon looked the same), and a
/// microphone that heard nothing. Each now has its own shape — a pulsing ring, a running timer with
/// level bars driven by the recorder's own amplitude, and a spinner where the send icon was.
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
    this.levelOf,
  });

  final TextEditingController controller;
  final bool recording;

  /// A turn is in flight: the send control becomes a spinner and the field goes read-only.
  final bool busy;
  final bool writing;
  final bool micEnabled;
  final VoidCallback onMic;
  final VoidCallback onToggleWriting;
  final VoidCallback onSend;
  final VoidCallback onTextChanged;

  /// The recorder's current input level in dBFS, or null on a platform that reports none (the bars
  /// then hold a static shape). Polled while recording only.
  final Future<double?> Function()? levelOf;

  @override
  State<AiChatComposer> createState() => _AiChatComposerState();
}

class _AiChatComposerState extends State<AiChatComposer> {
  /// How often the meter is sampled. Fast enough to follow speech, slow enough that the poll is
  /// invisible next to the audio pipeline running it.
  static const _meterInterval = Duration(milliseconds: 120);

  Timer? _meter;
  final Stopwatch _clock = Stopwatch();
  double? _level;

  @override
  void initState() {
    super.initState();
    if (widget.recording) _startMeter();
  }

  @override
  void didUpdateWidget(covariant AiChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recording && !oldWidget.recording) {
      _startMeter();
    } else if (!widget.recording && oldWidget.recording) {
      _stopMeter();
    }
  }

  void _startMeter() {
    _meter?.cancel();
    _clock
      ..reset()
      ..start();
    _meter = Timer.periodic(_meterInterval, (_) => unawaited(_sample()));
  }

  Future<void> _sample() async {
    if (!mounted || !widget.recording) return;
    final read = widget.levelOf;
    final next = read == null ? null : await read();
    if (!mounted || !widget.recording) return;
    setState(() => _level = next);
  }

  void _stopMeter() {
    _meter?.cancel();
    _meter = null;
    _clock
      ..stop()
      ..reset();
    _level = null;
  }

  @override
  void dispose() {
    _meter?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasText = widget.controller.text.trim().isNotEmpty;
    final showField = widget.writing || hasText;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

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
          if (widget.recording)
            _RecordingMeter(
              elapsed: _clock.elapsed,
              level: _level,
              animate: !still,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _MicButton(
                key: const ValueKey('ai-chat-mic'),
                recording: widget.recording,
                enabled: !widget.busy && widget.micEnabled,
                animate: !still,
                onTap: widget.onMic,
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
                    : InkWell(
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
              // A tap that has left for the model looks different from one that has not: the paper
              // plane is replaced by the spinner, so "did it send?" is answered by the control that
              // was tapped.
              _RoundAction(
                key: const ValueKey('ai-chat-send'),
                icon: LucideIcons.send,
                label: widget.busy ? 'Invio in corso' : 'Invia il messaggio',
                color: colors.red,
                busy: widget.busy,
                onTap: hasText && !widget.busy && !widget.recording ? widget.onSend : null,
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('ai-toggle-writing'),
              onPressed: widget.recording || widget.busy ? null : widget.onToggleWriting,
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

/// The microphone, with a ring that breathes while the recording is live.
///
/// The ring is the difference between "the button changed shape" and "the phone is listening": it
/// moves at a glance, from a phone held down at the hip. Reduced motion keeps the red circle and the
/// square and drops only the pulse.
class _MicButton extends StatefulWidget {
  const _MicButton({
    super.key,
    required this.recording,
    required this.enabled,
    required this.animate,
    required this.onTap,
  });

  final bool recording;
  final bool enabled;
  final bool animate;
  final VoidCallback onTap;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.recording && widget.animate) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.recording ? 'Ferma la registrazione' : 'Registra un messaggio',
      child: InkResponse(
        onTap: widget.enabled ? widget.onTap : null,
        radius: 28,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.recording && widget.animate)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => Container(
                    width: 44 + 12 * _pulse.value,
                    height: 44 + 12 * _pulse.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.red.withValues(alpha: 0.35 * (1 - _pulse.value)),
                    ),
                  ),
                ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.enabled ? colors.red : colors.bg3,
                ),
                child: Icon(
                  widget.recording ? LucideIcons.square : LucideIcons.mic,
                  size: 20,
                  color: widget.enabled ? Colors.white : colors.inkDisabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A recording is running: how long, and whether the microphone is hearing anything.
///
/// The timer is the recording's own age, and the bars follow the recorder's amplitude — the two
/// signals that tell "a microphone that is on" from "a microphone that is on and hearing silence",
/// which until now both looked like a red square.
class _RecordingMeter extends StatelessWidget {
  const _RecordingMeter({required this.elapsed, required this.level, required this.animate});

  final Duration elapsed;
  final double? level;
  final bool animate;

  /// Fixed silhouette, scaled by the live level: a row of bars all at the same height reads as a
  /// graphic, not as a meter.
  static const _shape = [0.45, 0.75, 1.0, 0.75, 0.45];

  /// Speech sits well above this, room noise just above the floor; below it the bars hold their
  /// idle height instead of collapsing to nothing (which would look broken).
  static const _floorDbfs = -60.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final db = level;
    final strength = db == null || db <= _floorDbfs
        ? 0.25
        : ((db - _floorDbfs) / -_floorDbfs).clamp(0.25, 1.0);
    final label =
        '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

    return Semantics(
      label: 'Registrazione in corso, $label',
      child: Padding(
        key: const ValueKey('ai-recording-indicator'),
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: colors.red),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              key: const ValueKey('ai-recording-timer'),
              style: TextStyle(
                fontFamily: 'IBM Plex Mono',
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: colors.ink,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  for (final (i, factor) in _shape.indexed) ...[
                    if (i > 0) const SizedBox(width: 3),
                    AnimatedContainer(
                      duration: animate ? const Duration(milliseconds: 120) : Duration.zero,
                      curve: Curves.easeOut,
                      width: 4,
                      height: 4 + 14 * factor * strength,
                      decoration: BoxDecoration(
                        color: colors.red.withValues(alpha: 0.45 + 0.55 * strength),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool busy;

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
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: CircularProgressIndicator(
                    key: const ValueKey('ai-sending-indicator'),
                    strokeWidth: 2,
                    color: colors.inkMuted,
                  ),
                )
              : Icon(icon, size: 20, color: enabled ? Colors.white : colors.inkDisabled),
        ),
      ),
    );
  }
}
