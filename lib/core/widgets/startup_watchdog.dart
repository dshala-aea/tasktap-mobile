import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/auth_providers.dart';
import '../../presentation/providers/kiosk_providers.dart';

/// Last-resort visible fallback for a cold start that never finishes (App Store rejection of
/// build 1.0 (50): "stuck on the splash screen").
///
/// The router stays on its initial route while `kioskModeProvider.loading` or
/// `authStateProvider.isLoading` is true. Each of those now has its own bounded timeouts, but if
/// anything still keeps either one loading for [threshold], this overlays a full-screen Italian
/// message with "Riprova", which invalidates both providers (re-running the kiosk read and the
/// session restore). The overlay disappears the moment loading finishes.
///
/// Inert once loaded: the timer exists only while something is loading and is cancelled as soon
/// as loading ends or the widget is disposed.
class StartupWatchdog extends ConsumerStatefulWidget {
  const StartupWatchdog({
    super.key,
    required this.child,
    this.threshold = const Duration(seconds: 10),
  });

  final Widget child;
  final Duration threshold;

  @override
  ConsumerState<StartupWatchdog> createState() => _StartupWatchdogState();
}

class _StartupWatchdogState extends ConsumerState<StartupWatchdog> {
  Timer? _timer;
  bool _tripped = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sync(bool loading) {
    if (loading) {
      // Arm once per loading episode; a repeated build while loading must not push it back.
      if (_timer == null && !_tripped) {
        _timer = Timer(widget.threshold, () {
          _timer = null;
          if (mounted) setState(() => _tripped = true);
        });
      }
    } else {
      _timer?.cancel();
      _timer = null;
      if (_tripped) {
        // Flipping state during build is not allowed; settle after this frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _tripped) setState(() => _tripped = false);
        });
      }
    }
  }

  void _retry() {
    // Re-arm for the retried attempt: hide the message, let the providers go loading again.
    setState(() => _tripped = false);
    ref.invalidate(kioskModeProvider);
    ref.invalidate(authRepositoryProvider);
    ref.invalidate(authStateProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Both watched unconditionally (no `||` short-circuit): a provider only starts listening to
    // its stream once something watches it, so skipping one would also skip its subscription.
    final kioskLoading = ref.watch(kioskModeProvider.select((s) => s.loading));
    final authLoading = ref.watch(authStateProvider.select((s) => s.isLoading));
    final loading = kioskLoading || authLoading;
    _sync(loading);

    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        Positioned.fill(child: widget.child),
        if (_tripped && loading)
          Positioned.fill(child: _StartupFailureScreen(onRetry: _retry)),
      ],
    );
  }
}

class _StartupFailureScreen extends StatelessWidget {
  const _StartupFailureScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_outlined, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Impossibile avviare TaskTap',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "L'avvio sta richiedendo più tempo del previsto. "
                    'Controlla la connessione e riprova.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onRetry, child: const Text('Riprova')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
