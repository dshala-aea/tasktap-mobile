// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// The input row under the chat: one row, one decision.
///
/// Voice is the primary path (ADR-0023: the recording is the model's input); the text field is the
/// quiet alternate for noisy sites and no-signal dictation. Both used to announce themselves with
/// their own band — a hint line, a red "Preferisci scrivere?" toggle, a dead paper plane — three
/// bands of controls under a conversation that the technician is trying to read. The row now says
/// exactly one thing at a time:
///
/// - nothing said yet: the microphone is the one loud control, next to a line that opens the
///   keyboard ("Tocca per scrivere" — the hint does what it says);
/// - recording: the stop disc, a running timer and the level bars, and nothing else — nothing can
///   be sent while a recording is open, so nothing offers to;
/// - text present: the paper plane appears, because now there is something to send.
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
    this.micProminent = true,
    this.canSend = true,
    this.levelOf,
  });

  final TextEditingController controller;
  final bool recording;

  /// A turn is in flight: the send control becomes a spinner and the field goes read-only.
  final bool busy;
  final bool writing;
  final bool micEnabled;

  /// Whether the microphone is the screen's primary action. True until the technician has said
  /// something: after the first turn the next step is what the footer offers, and two solid Stamp
  /// Red controls in one viewport would each claim to be it.
  final bool micProminent;

  /// Whether a turn may be started at all right now: false while one sits unsent — its retry or
  /// discard is the only way forward, and a second send beside it would compete with them.
  final bool canSend;

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
    // The plane appears when there is something to send, and stays for the turn it started — but
    // never while a recording is open: that turn's input is the audio, and a disabled plane beside
    // the meter is one more control saying nothing.
    final showSend = (hasText && !widget.recording) || widget.busy;

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _MicButton(
            key: const ValueKey('ai-chat-mic'),
            recording: widget.recording,
            prominent: widget.micProminent,
            enabled: !widget.busy && widget.micEnabled,
            animate: !still,
            onTap: widget.onMic,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: widget.recording
                ? _RecordingMeter(elapsed: _clock.elapsed, level: _level, animate: !still)
                : showField
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'Tocca per scrivere',
                        style: TextStyle(
                          fontFamily: 'Archivo',
                          fontSize: 13,
                          color: colors.inkMuted,
                        ),
                      ),
                    ),
                  ),
          ),
          if (showSend) ...[
            const SizedBox(width: AppSpacing.sm),
            _RoundAction(
              key: const ValueKey('ai-chat-send'),
              icon: LucideIcons.send,
              label: widget.busy ? 'Invio in corso' : 'Invia il messaggio',
              color: colors.red,
              busy: widget.busy,
              // A typed turn costs what a spoken one costs, so the same gate that dims the
              // microphone dims the plane: offering a send the server has already refused once is
              // how a screen comes to feel broken.
              onTap:
                  hasText && !widget.busy && !widget.recording && widget.micEnabled && widget.canSend
                  ? widget.onSend
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// The microphone: the one loud control until something has been said, then a quiet one.
///
/// A ring breathes while the recording is live — the difference between "the button changed shape"
/// and "the phone is listening", read at a glance from a phone held at the hip. Reduced motion keeps
/// the disc and the square and drops only the pulse.
class _MicButton extends StatefulWidget {
  const _MicButton({
    super.key,
    required this.recording,
    required this.prominent,
    required this.enabled,
    required this.animate,
    required this.onTap,
  });

  final bool recording;
  final bool prominent;
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
    final filled = widget.prominent || widget.recording;
    final enabled = widget.enabled || widget.recording;

    return Semantics(
      button: true,
      enabled: enabled,
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
                  color: !widget.enabled
                      ? colors.bg3
                      : filled
                      ? colors.red
                      : colors.surface,
                  border: Border.all(
                    color: !widget.enabled
                        ? colors.bg3
                        : filled
                        ? colors.red
                        : colors.borderLight,
                  ),
                ),
                child: Icon(
                  widget.recording ? LucideIcons.square : LucideIcons.mic,
                  size: 20,
                  color: !widget.enabled
                      ? colors.inkDisabled
                      : filled
                      ? Colors.white
                      : colors.accentInk,
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
/// which used to look identical: a red square and a sentence explaining it.
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
    final label = '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

    return Semantics(
      label: 'Registrazione in corso, $label',
      child: Row(
        key: const ValueKey('ai-recording-indicator'),
        children: [
          Text(
            label,
            key: const ValueKey('ai-recording-timer'),
            style: TextStyle(
              fontFamily: 'IBM Plex Mono',
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: colors.ink,
            ),
          ),
          const SizedBox(width: 12),
          for (final (i, factor) in _shape.indexed) ...[
            if (i > 0) const SizedBox(width: 3),
            AnimatedContainer(
              duration: animate ? const Duration(milliseconds: 120) : Duration.zero,
              curve: Curves.easeOut,
              width: 4,
              height: 4 + 16 * factor * strength,
              decoration: BoxDecoration(
                color: colors.red.withValues(alpha: 0.45 + 0.55 * strength),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
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
