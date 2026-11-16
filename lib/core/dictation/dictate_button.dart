// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_palette.dart';
import '../widgets/app_toast.dart';
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

    // One recogniser, one field: starting here must end whichever other field's session is live,
    // or the first button keeps reading "listening" while this one captures the words.
    if (service.isListening) await service.stop();
    if (!mounted) return;

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
      onDone: (outcome) {
        if (!mounted) return;
        setState(() => _listening = false);
        // A session the service refused is reported with the *fresh* reason, not the generic one:
        // the button is rebuilt from the same provider the service just re-checked, so the message
        // under the tap is the one that explains it.
        final notice = outcome == DictationOutcome.unavailable
            ? _noticeFor(ref.read(dictationCapabilityProvider).asData?.value)
            : outcome.notice;
        if (notice != null) showAppToast(context, message: notice.message, tone: notice.tone);
      },
    );
  }

  /// The reason, as the capability currently reads — falling back to the outcome's own text when the
  /// provider has not produced a value.
  ({String message, ToastTone tone})? _noticeFor(DictationCapability? capability) {
    final message = capability?.unavailableMessage;
    if (message == null) return DictationOutcome.unavailable.notice;
    return (message: message, tone: ToastTone.warning);
  }

  /// The crossed-out microphone was tapped: this is the one moment to re-ask the question.
  ///
  /// The capability is resolved once and cached for the app's lifetime (several fields ask for it on
  /// every build), which means a technician who granted the microphone, or installed the Italian
  /// pack, after the first answer kept a microphone that said "unavailable" until the process
  /// restarted. Tapping it now re-probes; if the answer has changed, the same tap starts dictating
  /// instead of asking for a second one.
  Future<void> _explain() async {
    ref.invalidate(dictationCapabilityProvider);
    final fresh = await ref.read(dictationCapabilityProvider.future);
    if (!mounted) return;
    if (fresh.canDictate) {
      await _toggle();
      return;
    }
    final notice = _noticeFor(fresh);
    if (notice == null) return;
    showAppToast(context, message: notice.message, tone: ToastTone.info);
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
            onPressed: _explain,
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
