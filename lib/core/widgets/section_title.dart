import 'package:flutter/material.dart';

import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Section heading row.
///
/// Spec: Sora 700/18 DARK; padding top 20 / horizontal 19 / bottom 10;
/// optional trailing [action] widget.
///
/// ```dart
/// SectionTitle(title: 'Attività recenti');
/// SectionTitle(title: 'Rapportini', action: TextButton(onPressed: ..., child: Text('Vedi tutti')));
/// ```
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.action, this.trailing});

  final String title;

  /// Optional right-side widget (e.g. a "Vedi tutti" TextButton).
  final Widget? action;

  /// Optional right-side text — a count or status that belongs to the section.
  ///
  /// Exists so a number does not need a card of its own to be readable. The dashboard's
  /// "2 di 5 completati" was a quarter of a 2×2 stat grid before it was four words in a heading.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 20, 19, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.colors.ink,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.colors.inkMuted,
              ),
            ),
          ?action,
        ],
      ),
    );
  }
}

/// A section label with no padding of its own, for use inside a card that already has some.
///
/// The rapportino wizard needed exactly this and, rather than having it, defined a private `_SL`
/// four times — byte-identical in `step_dettagli`, `step_ore`, `step_materiali_fold` and
/// `step_riepilogo`. Each one hardcoded `Color(0xFF363636)` as its ink, so in dark mode every
/// section heading in the app's primary daily flow was near-black text on a near-black ground.
/// Four copies also meant four places to fix it and no reason to expect anyone to find all four.
///
/// [SectionTitle] is the padded page-level heading; this is its in-card sibling. Both take ink
/// from the theme.
class StepLabel extends StatelessWidget {
  const StepLabel({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: context.colors.ink,
      ),
    );
  }
}
