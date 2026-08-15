// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../theme/app_colors.dart';
import '../widgets/widgets.dart';
import 'biometric_service.dart';

/// Holds the app behind a biometric prompt when the technician has asked for one.
///
/// Wraps the whole app rather than guarding the login route, because the thing being protected is
/// the data already on the device: an authenticated session survives a restart by design (that is
/// what makes the app usable with no signal), so "logged in" is not a lock. The phone gets handed
/// around a site, and this is what stops the person holding it reading customer and intervento
/// data.
///
/// Locks on cold start and again whenever the app returns from the background — a lock that only
/// ran once at launch would be open for the rest of the day.
class BiometricLock extends ConsumerStatefulWidget {
  const BiometricLock({super.key, required this.enabled, required this.child});

  /// The Impostazioni setting. False means this widget is a pass-through.
  final bool enabled;

  final Widget child;

  @override
  ConsumerState<BiometricLock> createState() => _BiometricLockState();
}

class _BiometricLockState extends ConsumerState<BiometricLock> with WidgetsBindingObserver {
  bool _locked = false;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) {
      _locked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _prompt());
    }
  }

  @override
  void didUpdateWidget(BiometricLock old) {
    super.didUpdateWidget(old);
    // Switched on in Settings: take effect now, not at the next cold start.
    if (widget.enabled && !old.enabled) {
      setState(() => _locked = true);
      _prompt();
    } else if (!widget.enabled && old.enabled) {
      setState(() => _locked = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enabled) return;

    // Re-lock on the way out, not on the way back. `paused` fires before the app appears in the
    // task switcher, so the lock is already painted over the content in the snapshot the OS takes.
    if (state == AppLifecycleState.paused && !_prompting) {
      setState(() => _locked = true);
    } else if (state == AppLifecycleState.resumed && _locked && !_prompting) {
      _prompt();
    }
  }

  Future<void> _prompt() async {
    if (_prompting) return;
    _prompting = true;
    try {
      final ok = await ref
          .read(biometricServiceProvider)
          .authenticate(reason: 'Sblocca TaskTap per accedere ai dati di clienti e interventi');
      if (mounted && ok) setState(() => _locked = false);
    } finally {
      _prompting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !_locked) return widget.child;

    // The child stays in the tree beneath the lock so its state — a running timer, a half-written
    // rapportino — survives being locked. It is covered, not disposed.
    return Stack(
      children: [
        widget.child,
        const Positioned.fill(child: _LockScreen()),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      // Opaque, and dark under both themes like the other full-bleed surfaces. Anything
      // translucent would leave the data legible behind the lock, which is the whole point.
      color: AppColors.punchGround,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.fingerprint, size: 40, color: AppColors.Y),
                const SizedBox(height: 20),
                const Text(
                  'TaskTap è bloccato',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onDark,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sblocca con impronta o Face ID per accedere ai dati di clienti e interventi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    color: AppColors.onDarkMuted,
                  ),
                ),
                const SizedBox(height: 24),
                Builder(
                  builder: (context) => AppButton(
                    label: 'Sblocca',
                    fullWidth: false,
                    icon: const Icon(LucideIcons.fingerprint, size: 16),
                    // A retry, because the OS prompt can be dismissed and a lock with no way back
                    // in is a lock-out.
                    onPressed: () =>
                        context.findAncestorStateOfType<_BiometricLockState>()?._prompt(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
