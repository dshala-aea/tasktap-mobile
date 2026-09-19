// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_palette.dart';
import '../widgets/widgets.dart';
import 'dictation_capability.dart';
import 'dictation_service.dart';

/// Dictate into a text field, on devices that can do it without a network.
///
/// Absent — not disabled, not broken — where the handset cannot. A microphone that is present but
/// refuses to work reads as a bug, and the technician retries it; nothing is a more reliable way
/// to make a working app feel unreliable. Where dictation is unavailable the field is simply an
/// ordinary text field, and the rapportino is completed by typing, exactly as before.
///
/// The reason is available on demand rather than shown permanently: it matters once, the first
/// time someone wonders where the microphone is, and taking a line of every form forever to
/// explain an absence is a worse trade than a tap.
class DictateButton extends ConsumerStatefulWidget {
  const DictateButton({
    super.key,
    required this.controller,
    required this.onChanged,
    this.explainWhenUnavailable = true,
  });

  /// The field being dictated into. Transcript is appended to whatever is already there, so
  /// speaking does not silently discard something already typed.
  final TextEditingController controller;

  /// Kept in step with the controller, because the editor's state — not the controller — is what
  /// reaches the draft row and then the submit payload.
  final ValueChanged<String> onChanged;

  /// When false the widget renders nothing at all on incapable devices, with no explanation
  /// affordance. For places where a second control would crowd the row.
  final bool explainWhenUnavailable;

  @override
  ConsumerState<DictateButton> createState() => _DictateButtonState();
}

class _DictateButtonState extends ConsumerState<DictateButton> {
  bool _listening = false;

  /// What was in the field before dictation started, so partial results replace each other rather
  /// than accumulating — the recogniser re-sends the whole utterance as it refines it.
  String _base = '';

  Future<void> _toggle() async {
    final service = ref.read(dictationServiceProvider);

    if (_listening) {
      await service.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    _base = widget.controller.text;
    setState(() => _listening = true);

    await service.start(
      onTranscript: (transcript) {
        if (!mounted) return;
        final separator = _base.isEmpty || _base.endsWith(' ') ? '' : ' ';
        final text = '$_base$separator$transcript';
        widget.controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        widget.onChanged(text);
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
  }

  void _explain(DictationCapability capability) {
    final message = capability.unavailableMessage;
    if (message == null) return;
    showAppToast(context, message: message, tone: ToastTone.info);
  }

  @override
  Widget build(BuildContext context) {
    final capability = ref.watch(dictationCapabilityProvider);

    return capability.when(
      // Nothing while the answer is unknown. A control that appears a beat late is better than one
      // that appears and then vanishes.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (capability) {
        if (!capability.canDictate) {
          if (!widget.explainWhenUnavailable) return const SizedBox.shrink();
          return IconButton(
            icon: Icon(LucideIcons.micOff, size: 18, color: context.colors.inkDisabled),
            tooltip: capability.unavailableMessage,
            onPressed: () => _explain(capability),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          );
        }

        return IconButton(
          icon: Icon(
            _listening ? LucideIcons.square : LucideIcons.mic,
            size: 18,
            color: _listening ? context.colors.red : context.colors.ink,
          ),
          tooltip: _listening ? 'Ferma dettatura' : 'Detta',
          onPressed: _toggle,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        );
      },
    );
  }
}
