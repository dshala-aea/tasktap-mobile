// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/icons/app_lucide_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import 'ai_card.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 1 of the AI report flow: "Descrivi le attività svolte".
//
// Presentation only. Every action here is the AI screen's existing one — the mic starts/stops the
// same VoiceCaptureController recording that becomes an uploaded `audioRef` turn (ADR-0023), the
// field is the same text the typed turn sent. Nothing in this file talks to the server.
//
// The waveform the design pack draws is deliberately absent: the recorder exposes no amplitude, and
// a bar chart that moved on a timer would be the one thing on this screen pretending to be data. The
// pulsing halos carry the "in ascolto" state instead, and they stop when the system asks for reduced
// motion.
// ══════════════════════════════════════════════════════════════════════════════

class AiDescribeStep extends StatefulWidget {
  const AiDescribeStep({
    super.key,
    required this.recording,
    required this.busy,
    required this.thinkingLabel,
    required this.voiceDisabled,
    required this.controller,
    required this.writing,
    required this.onToggleWriting,
    required this.onMic,
    this.onTextChanged,
  });

  /// A recording is running right now.
  final bool recording;

  /// A turn is in flight: the mic is replaced by a spinner and the footer is disabled.
  final bool busy;

  /// What the in-flight turn is doing, staged client-side by the caller.
  final String thinkingLabel;

  /// Voice capture is off for the whole company.
  final bool voiceDisabled;

  final TextEditingController controller;

  /// The technician chose to write instead of speaking.
  final bool writing;
  final VoidCallback onToggleWriting;

  final VoidCallback onMic;

  /// The description changed. The footer's "Genera il rapporto" lives in the parent, so it has to
  /// hear about it — without this the button stayed disabled while the technician typed.
  final VoidCallback? onTextChanged;

  @override
  State<AiDescribeStep> createState() => _AiDescribeStepState();
}

class _AiDescribeStepState extends State<AiDescribeStep> {
  Timer? _ticker;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    if (widget.recording) _startTicker();
  }

  @override
  void didUpdateWidget(AiDescribeStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recording && !oldWidget.recording) {
      _elapsed = 0;
      _startTicker();
    } else if (!widget.recording && oldWidget.recording) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _mmss {
    final m = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.base,
        AppSpacing.pagePadding,
        AppSpacing.base,
      ),
      children: [
        AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AiLabel('Passo 1 di 3'),
              const SizedBox(height: 3),
              Text(
                'Descrivi le attività svolte',
                style: TextStyle(
                  fontFamily: 'Archivo Narrow',
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: context.colors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const AiHelper(
                "Spiega con parole tue cosa hai fatto: al rapporto pensa l'assistente AI.",
              ),
            ],
          ),
        ),
        const AiCardGap(),
        AiCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          child: Column(
            children: [
              _MicOrb(
                recording: widget.recording,
                busy: widget.busy,
                onTap: widget.busy ? null : widget.onMic,
              ),
              const SizedBox(height: 12),
              Text(
                widget.busy
                    // The caller stages this through the turn's own ~45s: one frozen string for that
                    // long reads as a hung app. Uppercased here, not in the source copy, so the same
                    // sentences can be reused wherever the screen speaks in normal case.
                    ? widget.thinkingLabel.toUpperCase()
                    : widget.recording
                    ? '● IN ASCOLTO · $_mmss'
                    : hasText
                    ? 'TOCCA PER CONTINUARE'
                    : 'TOCCA PER INIZIARE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'IBM Plex Mono',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                  color: widget.busy ? context.colors.inkMuted : context.colors.red,
                ),
              ),
            ],
          ),
        ),
        if (widget.voiceDisabled)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: AiHelper(
              'La registrazione vocale non è attiva per questa azienda: scrivi la descrizione.',
            ),
          ),
        if (!widget.busy)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(
              child: TextButton(
                key: const ValueKey('ai-toggle-writing'),
                onPressed: widget.recording ? null : widget.onToggleWriting,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                child: Text(
                  widget.writing ? 'Descrivi a voce' : 'Preferisci scrivere?',
                  style: TextStyle(
                    fontFamily: 'Archivo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.colors.red,
                  ),
                ),
              ),
            ),
          ),
        if (widget.writing)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: AiCard(
              child: TextField(
                key: const ValueKey('ai-description-field'),
                controller: widget.controller,
                enabled: !widget.busy,
                minLines: 4,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: 'Cosa hai fatto, quali materiali hai usato, quanto tempo…',
                ),
                style: TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 14,
                  height: 1.4,
                  color: context.colors.ink,
                ),
                onChanged: (_) {
                  setState(() {});
                  widget.onTextChanged?.call();
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// The 120 pt red orb with its two halos, or a spinner while the assistant is compiling.
class _MicOrb extends StatefulWidget {
  const _MicOrb({required this.recording, required this.busy, required this.onTap});

  final bool recording;
  final bool busy;
  final VoidCallback? onTap;

  @override
  State<_MicOrb> createState() => _MicOrbState();
}

class _MicOrbState extends State<_MicOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.recording) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_MicOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recording && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.recording && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.busy) {
      return SizedBox(
        width: 120,
        height: 120,
        child: Center(
          child: SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 5,
              valueColor: AlwaysStoppedAnimation<Color>(context.colors.red),
            ),
          ),
        ),
      );
    }

    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Semantics(
      button: true,
      label: widget.recording ? 'Ferma la descrizione' : 'Inizia a descrivere',
      child: SizedBox(
        width: 156,
        height: 156,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = reduceMotion ? 0.5 : 0.5 + _pulse.value * 0.5;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    _halo(context, 156, 0.08 * t),
                    _halo(context, 136, 0.14 * t),
                  ],
                );
              },
            ),
            GestureDetector(
              onTap: widget.onTap,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(color: context.colors.red, shape: BoxShape.circle),
                child: Icon(
                  widget.recording ? LucideIcons.square : LucideIcons.mic,
                  size: 46,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _halo(BuildContext context, double size, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: context.colors.red.withValues(alpha: opacity),
      shape: BoxShape.circle,
    ),
  );
}
