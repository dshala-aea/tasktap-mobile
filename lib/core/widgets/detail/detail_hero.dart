import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_rack.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_colors.dart';
import '../../theme/status_colors.dart';
import '../app_card.dart';
import '../status_stamp.dart';

/// The app's minimum touch target for the hero's primary action. The mockup draws it at 42; the
/// extra 6px keeps it a 48px target without visibly changing the layout.
const double _primaryMinHeight = 48;

/// Secondary row buttons: the mockup draws 36, the app floors every standalone control at 44.
const double _rowMinHeight = 44;

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

/// One compact label/value pair, rendered by `DetailFactsGrid`.
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
/// The hero is two things: the header above the card ([kicker], [title], [subtitle]) and the card
/// itself (state label, [liveValue], [heroCopy], actions). Facts do not live here: they render in a
/// `DetailFactsGrid` inside the screen's Sintesi section.
class DetailHeroData {
  const DetailHeroData({
    required this.title,
    required this.variant,
    required this.status,
    this.kind,
    this.kicker,
    this.kickerContext,
    this.subtitle,
    this.heroCopy,
    this.liveValue,
    this.primaryAction,
    this.secondaryActions = const [],
  });

  final String title;
  final DetailHeroVariant variant;
  final DetailStatus status;

  /// The mono label inside a summary hero's top row, e.g. `Summary · cliente`.
  ///
  /// Operational heroes keep the current status-label treatment; summary heroes (the 10 master
  /// data details) render a [StatusStamp] on the right instead, matching `other-details.html`.
  final String? kind;

  /// The red part of the mono kicker row above the title, e.g. `TICKET · INT-2026-0412`.
  final String? kicker;

  /// The muted part after the kicker's `·`, e.g. `OGGI`.
  final String? kickerContext;

  /// Muted lines under the title (up to two).
  final String? subtitle;

  /// The line under the state label / timer row. Rendered 11.5 muted; wrap emphasis in a bold
  /// [TextSpan] / `Text.rich`.
  final Widget? heroCopy;

  final Widget? liveValue;
  final DetailAction? primaryAction;
  final List<DetailAction> secondaryActions;
}

/// The shared entity header for every detail screen — "Hero + stack", Option A of
/// `prototypes/detail-layouts.html`.
///
/// Above, outside the card: a mono kicker row, the Archivo Narrow title and a muted subtitle. Then a
/// flat [AppCard] sheet: mono state label and live value on top, a copy line, the full-width
/// primary action and one row of secondary actions. Il Documento only — 1px border, 2px radius, no
/// shadow.
class DetailHero extends StatelessWidget {
  const DetailHero({super.key, required this.data});

  final DetailHeroData data;

  @override
  Widget build(BuildContext context) {
    return switch (data.variant) {
      DetailHeroVariant.operational => _buildOperational(context),
      DetailHeroVariant.summary => _buildSummary(context),
    };
  }

  Widget _buildKicker(BuildContext context) {
    if (data.kicker == null && data.kickerContext == null) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final kickerStyle = AppTextStyles.docCode.copyWith(
      fontSize: 9,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.9,
      color: colors.inkMuted,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          if (data.kicker != null)
            Flexible(
              child: Text(
                data.kicker!.toUpperCase(),
                key: const Key('detail-hero-kicker'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kickerStyle.copyWith(color: colors.accentInk),
              ),
            ),
          if (data.kicker != null && data.kickerContext != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('·', style: kickerStyle),
            ),
          if (data.kickerContext != null)
            Text(data.kickerContext!.toUpperCase(), style: kickerStyle),
        ],
      ),
    );
  }

  Widget _buildOperational(BuildContext context) {
    final colors = context.colors;
    final showLive = data.liveValue != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildKicker(context),
        Text(
          data.title,
          key: const Key('detail-hero-title'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.displayLarge.copyWith(
            fontSize: 30,
            height: 0.98,
            letterSpacing: -0.75,
            color: colors.ink,
          ),
        ),
        if (data.subtitle != null) ...[
          const SizedBox(height: 7),
          Text(
            data.subtitle!,
            key: const Key('detail-hero-subtitle'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              fontSize: 11.5,
              height: 1.45,
              color: colors.inkMuted,
            ),
          ),
        ],
        SizedBox(height: data.subtitle != null ? 14 : 12),
        AppCard(
          key: const Key('detail-hero-card'),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    data.status.label.toUpperCase(),
                    style: AppTextStyles.docCode.copyWith(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.9,
                      color: colors.inkMuted,
                    ),
                  ),
                  if (showLive)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: DefaultTextStyle.merge(
                          textAlign: TextAlign.right,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 11.5,
                            color: colors.inkMuted,
                          ),
                          child: data.liveValue!,
                        ),
                      ),
                    ),
                ],
              ),
              if (data.heroCopy != null) ...[
                const SizedBox(height: 6),
                DefaultTextStyle.merge(
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 11.5,
                    color: colors.inkMuted,
                  ),
                  child: data.heroCopy!,
                ),
              ],
              if (data.primaryAction != null) ...[
                SizedBox(height: data.heroCopy != null ? 13 : AppSpacing.md),
                _PrimaryAction(action: data.primaryAction!),
              ],
              if (data.secondaryActions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _SecondaryActions(actions: data.secondaryActions),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The master-data variant from `other-details.html`: the entity title and its facts line live
  /// inside the hero card, with a rotated status stamp in the top-right. `kind` names the subject
  /// (`Summary · cliente`); [DetailHeroData.kicker] stays the mono line above the card.
  Widget _buildSummary(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildKicker(context),
        AppCard(
          key: const Key('detail-hero-card'),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (data.kind != null)
                    Expanded(
                      child: Text(
                        data.kind!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.docCode.copyWith(
                          fontSize: 8,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.64,
                          color: colors.inkMuted,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 8),
                  StatusStamp(
                    stato: data.status.label,
                    size: StampSize.small,
                    family: _familyForTone(data.status.tone),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                data.title,
                key: const Key('detail-hero-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.displayLarge.copyWith(
                  fontSize: 22,
                  height: 1,
                  letterSpacing: -0.44,
                  color: colors.ink,
                ),
              ),
              if (data.subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  data.subtitle!,
                  key: const Key('detail-hero-subtitle'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 9.5,
                    height: 1.4,
                    color: colors.inkMuted,
                  ),
                ),
              ],
              if (data.heroCopy != null) ...[
                const SizedBox(height: 6),
                DefaultTextStyle.merge(
                  style: AppTextStyles.bodySmall.copyWith(
                    fontSize: 9.5,
                    height: 1.4,
                    color: colors.inkMuted,
                  ),
                  child: data.heroCopy!,
                ),
              ],
              if (data.primaryAction != null) ...[
                const SizedBox(height: 8),
                _PrimaryAction(action: data.primaryAction!),
              ],
              if (data.secondaryActions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _SecondaryActions(actions: data.secondaryActions),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static StatusFamily _familyForTone(DetailStatusTone tone) {
    return switch (tone) {
      DetailStatusTone.neutral => StatusFamily.neutral,
      DetailStatusTone.info => StatusFamily.info,
      DetailStatusTone.good => StatusFamily.good,
      DetailStatusTone.warn => StatusFamily.warn,
      DetailStatusTone.bad => StatusFamily.bad,
    };
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
        DetailHeroButton(
          label: action.label,
          icon: action.icon,
          onPressed: action.enabled ? action.onPressed : null,
          variant: DetailHeroButtonVariant.primary,
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
            child: DetailHeroButton(
              label: actions[i].label,
              icon: actions[i].icon,
              onPressed: actions[i].enabled ? actions[i].onPressed : null,
              variant: i == 0
                  ? DetailHeroButtonVariant.secondary
                  : DetailHeroButtonVariant.ghost,
            ),
          ),
        ],
      ],
    );
  }
}

enum DetailHeroButtonVariant { primary, secondary, ghost }

/// The hero's own button: the mockup's `.btn` — 2px radius, Archivo 12/600 (11 in the secondary
/// row), flat fill. `AppButton` rounds at 16 and sets Archivo Narrow, which is not this design.
class DetailHeroButton extends StatelessWidget {
  const DetailHeroButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = DetailHeroButtonVariant.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final DetailHeroButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = variant == DetailHeroButtonVariant.primary;
    final enabled = onPressed != null;

    final bg = switch (variant) {
      DetailHeroButtonVariant.primary => AppColors.Y,
      DetailHeroButtonVariant.secondary => colors.bg3,
      DetailHeroButtonVariant.ghost => Colors.transparent,
    };
    final fg = switch (variant) {
      DetailHeroButtonVariant.primary => colors.brandOn,
      DetailHeroButtonVariant.secondary => colors.ink,
      DetailHeroButtonVariant.ghost => colors.inkMuted,
    };
    final style = TextStyle(
      fontFamily: 'Archivo',
      fontSize: primary ? 12 : 11,
      fontWeight: variant == DetailHeroButtonVariant.ghost
          ? FontWeight.w500
          : FontWeight.w600,
      letterSpacing: primary ? 0.12 : 0,
      color: enabled ? fg : fg.withAlpha(110),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: primary ? _primaryMinHeight : _rowMinHeight,
      ),
      child: Material(
        color: enabled ? bg : (primary ? bg.withAlpha(120) : bg),
        shape: RoundedRectangleBorder(
          borderRadius: AppRack.freeShape,
          side: variant == DetailHeroButtonVariant.secondary
              ? BorderSide(color: colors.borderLight)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: primary ? 14 : 9,
              vertical: 8,
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    IconTheme(
                      data: IconThemeData(color: style.color, size: 14),
                      child: icon!,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: style,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
