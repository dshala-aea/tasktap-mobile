// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_palette.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_card.dart';
import '../widgets/app_toast.dart';
import 'dictation_capability.dart';
import 'dictation_service.dart';
import 'dictation_target.dart';

/// The one microphone a step owns, pinned below its form — outside the fields it writes into.
///
/// Replaces the per-field suffix microphone: a technician no longer has to pick the field first
/// and then aim at a small icon on its edge. It writes into the field last touched and names that
/// field on the bar, so the destination is stated rather than assumed.
class DictationBar extends ConsumerStatefulWidget {
  const DictationBar({super.key, required this.registry});

  final DictationTargetRegistry registry;

  @override
  ConsumerState<DictationBar> createState() => _DictationBarState();
}

class _DictationBarState extends ConsumerState<DictationBar> {
  bool _listening = false;

  /// What was in the field before this session started, so partial results replace each other
  /// rather than accumulating — the recogniser re-sends the whole utterance as it refines it.
  String _base = '';

  /// The field this session was started on, locked rather than re-read per transcript: the words
  /// belong to the field the technician was in when they started speaking. Tapping a different
  /// field ends the session (see [_onRegistryChanged]), so one utterance can never silently split
  /// across two fields.
  DictationTarget? _sessionTarget;

  @override
  void initState() {
    super.initState();
    widget.registry.addListener(_onRegistryChanged);
  }

  @override
  void dispose() {
    widget.registry.removeListener(_onRegistryChanged);
    super.dispose();
  }

  void _onRegistryChanged() {
    if (!mounted) return;
    setState(() {});
    // Tapping another field is a clear intent to redirect, and stopping is more predictable than
    // silently retargeting: the technician sees one session end and starts the next deliberately.
    if (_listening && widget.registry.active?.id != _sessionTarget?.id) {
      unawaited(_stop());
    }
  }

  Future<void> _stop() async {
    await ref.read(dictationServiceProvider).stop();
    if (!mounted) return;
    setState(() => _listening = false);
  }

  Future<void> _toggle() async {
    final target = widget.registry.active;
    if (target == null) return;

    if (_listening) {
      await _stop();
      return;
    }

    final service = ref.read(dictationServiceProvider);
    _base = target.controller.text;
    _sessionTarget = target;
    setState(() => _listening = true);

    // The keyboard and the microphone are two people talking at once, and only one of them can be
    // listened to. The registry already remembers the field, so dropping focus loses nothing.
    FocusScope.of(context).unfocus();

    await service.start(
      onTranscript: (transcript) {
        if (!mounted) return;
        final separator = _base.isEmpty || _base.endsWith(' ') ? '' : ' ';
        final text = '$_base$separator$transcript';
        target.controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        target.onChanged(text);
      },
      onDone: (outcome) {
        if (!mounted) return;
        setState(() => _listening = false);
        final notice = outcome.notice;
        if (notice != null) showAppToast(context, message: notice.message, tone: notice.tone);
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
    return ref
        .watch(dictationCapabilityProvider)
        .when(
          // Nothing while the answer is unknown. A control that appears a beat late is better than
          // one that appears and then vanishes.
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (capability) {
            if (!capability.canDictate) {
              // The reason is permanent here, not on demand as in DictateButton — and that
              // difference is deliberate. Hiding why the step's one microphone is dead is the exact
              // bug this bar was built to fix, so the actionable half is always on screen.
              return _Bar(
                icon: LucideIcons.micOff,
                iconColor: context.colors.inkDisabled,
                titleColor: context.colors.inkDisabled,
                title: 'Dettatura non disponibile',
                subtitle: capability.unavailableHint ?? '',
                onTap: () => _explain(capability),
              );
            }

            final active = widget.registry.active;
            return _Bar(
              icon: _listening ? LucideIcons.square : LucideIcons.mic,
              iconColor: _listening ? context.colors.red : context.colors.ink,
              titleColor: context.colors.ink,
              title: _listening ? 'Dettando' : 'Detta',
              subtitle: active == null
                  ? 'Tocca un campo per scegliere dove scrivere.'
                  : 'Scrive in: ${active.label}',
              onTap: _toggle,
            );
          },
        );
  }
}

/// A card-shaped tap target: leading icon, bold title, muted subtitle.
///
/// [AppCard]'s own `onTap` supplies the Material/InkWell ripple and the rounded hit shape, so the
/// whole row — not just the icon — is the target, and MergeSemantics reads it as one control.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.icon,
    required this.iconColor,
    required this.titleColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color titleColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: AppCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: iconColor),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
