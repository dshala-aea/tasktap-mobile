import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/widgets.dart';
import '../../data/badge/badge_models.dart';
import 'badge_providers.dart';

/// "Il mio badge": the worker's identity card with a rotating QR a team leader scans at the
/// cantiere. The QR is always dark-on-white regardless of theme (scan reliability), and is only
/// ever drawn from a [BadgeReady] state — any other state hides it.
class MyBadgeScreen extends ConsumerStatefulWidget {
  const MyBadgeScreen({super.key});

  @override
  ConsumerState<MyBadgeScreen> createState() => _MyBadgeScreenState();
}

class _MyBadgeScreenState extends ConsumerState<MyBadgeScreen> {
  static const double _maxQr = 340;

  late final BadgeWakelock _wakelock;

  @override
  void initState() {
    super.initState();
    _wakelock = ref.read(badgeWakelockProvider);
    _wakelock.enable();
  }

  @override
  void dispose() {
    _wakelock.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(badgeControllerProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: 'Il mio badge', showBack: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.base,
                  AppSpacing.pagePadding,
                  AppSpacing.xxl,
                ),
                child: switch (state) {
                  BadgeReady(:final card) => _ReadyView(card: card, maxQr: _maxQr),
                  BadgeLoading() => const _MessageView(
                    message: 'Aggiornamento del badge…',
                    loading: true,
                  ),
                  BadgeRevoked() => const _MessageView(
                    message: 'Badge disattivato — contatta l\'ufficio',
                  ),
                  BadgeInactive() => const _MessageView(
                    message: 'Account disattivato — contatta l\'ufficio',
                  ),
                  BadgeOffline() => _MessageView(
                    message: 'Nessuna connessione — il badge richiede il segnale. Riprova',
                    onRetry: () => ref.read(badgeControllerProvider.notifier).refresh(),
                  ),
                  BadgeError() => _MessageView(
                    message: 'Impossibile aggiornare il badge. Riprova.',
                    onRetry: () => ref.read(badgeControllerProvider.notifier).refresh(),
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Server status (English enum name) -> Italian label. Unknown values return null and the status
/// text is hidden rather than leaking an English word. Add new members here.
const _statusLabels = <String, String>{'active': 'Attivo'};

String? statusLabel(String status) => _statusLabels[status.trim().toLowerCase()];

bool isActiveStatus(String status) => status.trim().toLowerCase() == 'active';

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.card, required this.maxQr});

  final BadgeCard card;
  final double maxQr;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        _Avatar(name: card.displayName, photoUrl: card.photoUrl),
        const SizedBox(height: AppSpacing.md),
        Text(
          card.displayName,
          style: AppTextStyles.headlineMedium.copyWith(color: c.ink),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          card.employerName,
          style: AppTextStyles.bodyLarge.copyWith(color: c.inkMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.base),
        LayoutBuilder(
          builder: (context, constraints) {
            // The white card's own padding comes off the width so the code itself is as large
            // as the screen allows, capped for tablets.
            final side = math.min(constraints.maxWidth - 2 * AppSpacing.base, maxQr);
            return Center(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.base),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                ),
                child: BadgeQrCode(data: card.token, size: side),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.base),
        if (statusLabel(card.status) != null) ...[
          Semantics(
            liveRegion: true,
            container: true,
            child: Text(
              statusLabel(card.status)!,
              style: AppTextStyles.titleMedium.copyWith(
                color: isActiveStatus(card.status) ? c.green : c.ink,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(
          'Mostra questo codice al caposquadra',
          style: AppTextStyles.bodySmall.copyWith(color: c.inkMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, this.loading = false, this.onRetry});

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxxl),
      child: Column(
        children: [
          if (loading) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.base),
          ],
          Semantics(
            liveRegion: true,
            container: true,
            child: Text(
              message,
              style: AppTextStyles.bodyLarge.copyWith(color: context.colors.ink),
              textAlign: TextAlign.center,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.base),
            AppButton(label: 'Riprova', onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.photoUrl});

  static const double _size = 96;

  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      key: const ValueKey('badge-initials'),
      width: _size,
      height: _size,
      alignment: Alignment.center,
      color: context.colors.bg3,
      child: Text(
        _initials(name),
        style: AppTextStyles.headlineLarge.copyWith(color: context.colors.ink),
      ),
    );
    final url = photoUrl;
    // `User.PhotoUrl` is a free string set by the admin/client (no upload endpoint, no API path),
    // so it is an external public URL: plain Image.network, initials when it fails.
    return ClipOval(
      child: url == null || url.isEmpty
          ? placeholder
          : Image.network(
              url,
              key: const ValueKey('badge-photo'),
              width: _size,
              height: _size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final second = parts.length > 1 ? parts.last.characters.first : '';
    return (first + second).toUpperCase();
  }
}

/// The QR itself: black modules on white, whatever the theme. Public so tests can assert on the
/// payload string ([data]) without decoding pixels.
class BadgeQrCode extends StatelessWidget {
  const BadgeQrCode({super.key, required this.data, required this.size});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: data,
      size: size,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      backgroundColor: Colors.white,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
  }
}
