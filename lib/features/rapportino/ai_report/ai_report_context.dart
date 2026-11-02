// dart format width=100
import 'package:flutter/material.dart';

import 'ai_card.dart';

// ══════════════════════════════════════════════════════════════════════════════
// "What this report is about", pinned above the Controlla cards.
//
// The review screen used to open on the assistant's own output alone: no ticket, no customer, no
// site. A technician who had just walked off a job saw a list of lines and no way to tell whether
// they belonged to the intervento they had come from — and when the assistant produced nothing,
// the screen opened genuinely blank. The link is known (the copilot is opened from a ticket), so
// naming it costs one row and makes an empty draft read as "nothing compiled yet" rather than as
// "wrong report".
// ══════════════════════════════════════════════════════════════════════════════

/// The entity a copilot session and the report it will produce belong to.
///
/// Every field is a display string resolved from the device's own mirror — an absent value is
/// simply not shown, never a placeholder, so a stale mirror degrades the card instead of lying
/// about it.
class AiReportContext {
  const AiReportContext({required this.ticketLabel, this.cliente, this.sede});

  /// "12 · Sostituzione filtro", or just the title when the ticket has no numero on this device.
  final String ticketLabel;

  final String? cliente;
  final String? sede;
}

class AiReportContextCard extends StatelessWidget {
  const AiReportContextCard({super.key, required this.context});

  final AiReportContext context;

  @override
  Widget build(BuildContext ctx) {
    final under = [
      if (context.cliente != null) 'Cliente · ${context.cliente}',
      if (context.sede != null) 'Sede · ${context.sede}',
    ];

    return AiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AiLabel('Intervento'),
          const SizedBox(height: 4),
          // AiValue wraps (it is a plain Text in a Column), unlike AiKvRow's value — which is a
          // bare Text inside a Row and would overflow on a long ticket title.
          AiValue(context.ticketLabel),
          if (under.isNotEmpty) ...[
            const SizedBox(height: 6),
            AiHelper(under.join(' · ')),
          ],
        ],
      ),
    );
  }
}
