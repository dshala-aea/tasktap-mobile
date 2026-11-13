// dart format width=100
import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';

/// Art. 50 transparency, stated permanently rather than only in the first-recording consent dialog:
/// the technician is talking to an AI assistant, messages go to an AI processor, and voice
/// recordings are sent for transcription.
class AiTransparencyNotice extends StatelessWidget {
  const AiTransparencyNotice({super.key});

  static const String text =
      'Stai interagendo con un assistente AI. I messaggi sono elaborati da un fornitore AI; '
      'le registrazioni vocali vengono inviate per la trascrizione.';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.pagePadding, 6, AppSpacing.pagePadding, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.alertCircle, size: 14, color: context.colors.inkMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11.5, height: 1.35, color: context.colors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}
