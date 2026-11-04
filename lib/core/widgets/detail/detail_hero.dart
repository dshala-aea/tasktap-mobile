import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_rack.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../app_button.dart';
import '../app_card.dart';
import '../app_tappable.dart';
import '../status_stamp.dart';

/// The app's minimum touch target. `AppButton` floors at 44; the hero lifts every actionable
/// element to 48 without changing the shared button widget itself.
const double _minTouchTarget = 48;

/// How a detail hero presents its entity.
///
/// [operational] screens (ticket, cantiere, rapportino) may show a live value — a running timer or
/// a day total. [summary] screens (master data) never do, even if a value is supplied.
enum DetailHeroVariant { operational, summary }

/// The semantic family a status belongs to, for consumers that need to react to its meaning
/// without parsing the Italian label.
///
/// The visible [StatusStamp] still resolves its own family through `statusFamilyOf`, exactly like
/// every other status display in the app; this enum is the data-level tone the shell can later use
/// for the collapsed bar and action gating.
enum DetailStatusTone { neutral, info, good, warn, bad }

/// One status line in a detail hero: the label rendered in the stamp, plus its semantic tone.
class DetailStatus {
  const DetailStatus({
    required this.label,
    this.tone = DetailStatusTone.neutral,
  });

  final String label;
  final DetailStatusTone tone;
}

/// One compact label/value pair shown under the hero title.
class DetailFact {
  const DetailFact({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;
}

/// One hero action. A disabled action keeps its label visible and states why it cannot run.
class DetailAction {
  const DetailAction({
    required this.label,
    this.icon,
    this.onPressed,
    this.enabled = true,
    this.disabledReason,
  });

  final String label;
  final Widget? icon;
  final VoidCallback? onPressed;
  final bool enabled;
  final String? disabledReason;
}

/// Everything a detail hero renders. Presentation only — no provider or network access.
///
/// More than three facts may be supplied; [DetailHero] renders only the first three.
class DetailHeroData {
  const DetailHeroData({
    required this.title,
    required this.variant,
    required this.status,
    this.subtitle,
    this.facts = const [],
    this.liveValue,
    this.primaryAction,
    this.secondaryActions = const [],
  });

  final String title;
  final DetailHeroVariant variant;
  final DetailStatus status;
  final String? subtitle;
  final List<DetailFact> facts;
  final Widget? liveValue;
  final DetailAction? primaryAction;
  final List<DetailAction> secondaryActions;
}

/// The shared entity header for every detail screen.
///
/// A flat [AppCard] sheet: status stamp and optional live value on top, a two-line title, an
/// optional mono reference, up to three facts, then the full-width primary action and one row of
/// secondary actions. Il Documento only — 1px border, 2px radius, no shadow.
class DetailHero extends StatelessWidget {
  const DetailHero({super.key, required this.data});

  final DetailHeroData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showLive =
        data.variant == DetailHeroVariant.operational && data.liveValue != null;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StatusStamp(stato: data.status.label),
              if (showLive)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: data.liveValue!,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            data.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.displayLarge.copyWith(
              fontSize: 28,
              color: colors.ink,
            ),
          ),
          if (data.subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              data.subtitle!,
              style: AppTextStyles.docCode.copyWith(
                fontSize: 11,
                color: colors.inkMuted,
              ),
            ),
          ],
          if (data.facts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.base),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                for (final fact in data.facts.take(3)) _FactTile(fact: fact),
              ],
            ),
          ],
          if (data.primaryAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _PrimaryAction(action: data.primaryAction!),
          ],
          if (data.secondaryActions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _SecondaryActions(actions: data.secondaryActions),
          ],
        ],
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.fact});

  final DetailFact fact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fact.label,
          style: AppTextStyles.labelSmall.copyWith(color: colors.inkMuted),
        ),
        const SizedBox(height: 2),
        Text(
          fact.value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    if (fact.onTap == null) return content;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _minTouchTarget),
      child: AppTappable(
        onTap: fact.onTap,
        borderRadius: AppRack.insetShape,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Center(widthFactor: 1, child: content),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.action});

  final DetailAction action;

  @override
  Widget build(BuildContext context) {
    final reason = !action.enabled ? action.disabledReason : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minTouchTarget),
          child: AppButton(
            label: action.label,
            icon: action.icon,
            onPressed: action.enabled ? action.onPressed : null,
            fullWidth: true,
          ),
        ),
        if (reason != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            reason,
            style: AppTextStyles.bodySmall.copyWith(
              color: context.colors.inkMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions({required this.actions});

  final List<DetailAction> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _minTouchTarget),
              child: i == 0
                  ? AppButton.secondary(
                      label: actions[i].label,
                      icon: actions[i].icon,
                      onPressed: actions[i].enabled
                          ? actions[i].onPressed
                          : null,
                      fullWidth: true,
                    )
                  : AppButton.ghost(
                      label: actions[i].label,
                      icon: actions[i].icon,
                      onPressed: actions[i].enabled
                          ? actions[i].onPressed
                          : null,
                      fullWidth: true,
                    ),
            ),
          ),
        ],
      ],
    );
  }
}
