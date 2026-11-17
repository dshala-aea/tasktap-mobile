import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/app_rack.dart';
import '../../theme/app_text_styles.dart';

/// One inline attachment — the mockup's `.attach`: a 28px icon box (Fill, 1px rule), 11/600 name
/// that ellipsizes, mono 8.5 size. Rows carry a top rule; the last one also a bottom rule.
class DetailAttachmentRow extends StatelessWidget {
  const DetailAttachmentRow({
    super.key,
    required this.name,
    required this.icon,
    this.size,
    this.isLast = false,
    this.onTap,
  });

  final String name;
  final Widget icon;
  final String? size;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rule = BorderSide(color: colors.borderLight);

    final row = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: rule, bottom: isLast ? rule : BorderSide.none),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.bg3,
              border: Border.fromBorderSide(rule),
              borderRadius: AppRack.freeShape,
            ),
            child: IconTheme(
              data: IconThemeData(color: colors.inkMuted, size: 14),
              child: Center(child: icon),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
            ),
          ),
          if (size != null) ...[
            const SizedBox(width: 9),
            Text(
              size!,
              style: AppTextStyles.docCode.copyWith(
                fontSize: 8.5,
                color: colors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}
