import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_text_styles.dart';

/// Minimum height/width of a tappable header element.
const double kDetailTapTarget = 44;

class DetailSectionData {
  const DetailSectionData({
    required this.title,
    required this.child,
    this.trailing,
    this.onTitleTap,
    this.isEmpty = false,
  });

  final String title;
  final Widget child;

  /// Mono 9px trailing slot — usually a [DetailSectionMeta] count or a [DetailSectionLink].
  final Widget? trailing;

  /// Makes the section title itself tappable (e.g. open the full compartment).
  final VoidCallback? onTitleTap;
  final bool isEmpty;
}

/// A muted mono trailing label in a section header, uppercased: `4 campi` -> `4 CAMPI`.
class DetailSectionMeta extends StatelessWidget {
  const DetailSectionMeta(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase());
}

/// A red mono `APRI`-style link in a section header.
class DetailSectionLink extends StatelessWidget {
  const DetailSectionLink({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        // 44px minimum touch target (padding only; the glyphs are unchanged).
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kDetailTapTarget,
            minWidth: kDetailTapTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                label.toUpperCase(),
                style: TextStyle(color: context.colors.accentInk),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.data});

  final DetailSectionData data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final tappable =
        data.onTitleTap != null || data.trailing is DetailSectionLink;

    Widget title = Text(
      data.title,
      style: AppTextStyles.headlineMedium.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.17,
        color: colors.ink,
      ),
    );
    if (data.onTitleTap != null) {
      title = InkWell(
        onTap: data.onTitleTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kDetailTapTarget),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: title,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: title),
            ),
            if (data.trailing != null)
              DefaultTextStyle.merge(
                style: AppTextStyles.docCode.copyWith(
                  fontSize: 9,
                  letterSpacing: 0.54,
                  color: colors.inkMuted,
                ),
                child: data.trailing!,
              ),
          ],
        ),
        // A tappable header is already 44px tall; the touch padding stands in for the gap.
        SizedBox(height: tappable ? 0 : 8),
        data.child,
      ],
    );
  }
}
