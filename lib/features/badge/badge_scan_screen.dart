import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/scanner/continuous_scan_view.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/widgets.dart';
import '../cantiere/cantiere_providers.dart';
import 'badge_scan_controller.dart';
import 'badge_scan_result_card.dart';

/// Builds the camera side of the screen and reports every detected code. Injectable so widget
/// tests drive scans with no camera.
typedef ScanSource = Widget Function(BuildContext context, void Function(String code) onCode);

Widget _defaultScanSource(BuildContext context, void Function(String code) onCode) =>
    ContinuousScanView(onCode: onCode);

/// The team leader's continuous badge scanner: camera on top (so the leader keeps aiming), the
/// newest result prominent below it, the session's earlier results under that. Online-only; the
/// list lives only while this screen is open.
class BadgeScanScreen extends ConsumerStatefulWidget {
  const BadgeScanScreen({super.key, required this.cantiereId, this.scanSource});

  final String cantiereId;
  final ScanSource? scanSource;

  @override
  ConsumerState<BadgeScanScreen> createState() => _BadgeScanScreenState();
}

class _BadgeScanScreenState extends ConsumerState<BadgeScanScreen> {
  void _onCode(String code) {
    unawaited(ref.read(badgeScanControllerProvider(widget.cantiereId).notifier).onCode(code));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entries = ref.watch(badgeScanControllerProvider(widget.cantiereId));
    final inFlight = ref.watch(badgeScanInFlightProvider(widget.cantiereId));
    final cantiereName = ref.watch(cantiereByIdProvider(widget.cantiereId)).valueOrNull?.name;
    final source = widget.scanSource ?? _defaultScanSource;
    final height = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: c.bg2,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(title: 'Scansiona badge', showBack: true),
            if (cantiereName != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
                child: Text(
                  cantiereName,
                  style: AppTextStyles.titleMedium.copyWith(color: c.inkMuted),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  key: const ValueKey('badge-scan-preview'),
                  height: height * 0.32,
                  child: source(context, _onCode),
                ),
              ),
            ),
            SizedBox(
              height: 32,
              child: inFlight
                  ? Semantics(
                      liveRegion: true,
                      child: Center(
                        child: Text(
                          'Verifica in corso…',
                          style: AppTextStyles.bodyMedium.copyWith(color: c.inkMuted),
                        ),
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        'Inquadra il badge del lavoratore',
                        style: AppTextStyles.bodyLarge.copyWith(color: c.inkMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.pagePadding,
                        0,
                        AppSpacing.pagePadding,
                        AppSpacing.xxl,
                      ),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) {
                        final card = BadgeScanResultCard(entry: entries[i], prominent: i == 0);
                        if (i != 0) return card;
                        // The newest result is announced to screen readers as it arrives.
                        return Semantics(
                          liveRegion: true,
                          container: true,
                          label: [
                            entries[i].outcome?.worker?.displayName,
                            presentBadgeScan(entries[i]).text,
                          ].whereType<String>().join(', '),
                          child: ExcludeSemantics(child: card),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
