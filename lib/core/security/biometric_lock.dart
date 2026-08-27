// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../presentation/providers/auth_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_vetro_palette.dart';
import '../widgets/widgets.dart';
import 'biometric_service.dart';

/// How long the app may be away before it asks for a fingerprint again.
///
/// The lock used to prompt on every single return to the foreground. A technician on a job checks
/// the address in Maps, photographs a serial number, answers a message, and comes back — four
/// fingerprint prompts to do one intervento. A control that fires that often stops being read and
/// starts being swatted away, and the usual next step is the technician turning it off entirely,
/// which leaves the data less protected than a lock that asks less.
///
/// Five minutes is the window in which the phone has almost certainly not left the hand it was in.
/// The threat this lock exists for — the handset being passed around a site, or left in a van —
/// takes longer than that to happen, and is still caught.
const Duration kBiometricGrace = Duration(minutes: 5);

/// Don't hammer the token endpoint on every glance at the screen.
const Duration _kSessionRefreshAfter = Duration(seconds: 60);

const String _kLastUnlockKey = 'biometric_last_active_at';

/// When the app was last known to be in the technician's hands.
///
/// An interface rather than a direct [FlutterSecureStorage] call so the grace window can be
/// tested without a keystore — and because "how long since the app was in use" is a question the
/// lock asks, not a storage detail it should own.
abstract interface class LockActivityStore {
  Future<DateTime?> lastActiveAt();

  Future<void> markActive(DateTime at);
}

/// The real one. Secure storage rather than SharedPreferences because this timestamp is what
/// decides whether a security control runs.
class SecureLockActivityStore implements LockActivityStore {
  const SecureLockActivityStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<DateTime?> lastActiveAt() async {
    try {
      final raw = await _storage.read(key: _kLastUnlockKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      // Keystore unavailable. Unknown reads as "too long ago", which is the safe direction.
      return null;
    }
  }

  @override
  Future<void> markActive(DateTime at) async {
    try {
      await _storage.write(key: _kLastUnlockKey, value: at.toIso8601String());
    } catch (_) {
      // The next cold start falls back to prompting. Safe direction again.
    }
  }
}

/// Holds the app behind a biometric prompt when the technician has asked for one.
///
/// Wraps the whole app rather than guarding the login route, because the thing being protected is
/// the data already on the device: an authenticated session survives a restart by design (that is
/// what makes the app usable with no signal), so "logged in" is not a lock. The phone gets handed
/// around a site, and this is what stops the person holding it reading customer and intervento
/// data.
///
/// Two things happen when the app comes back:
///
/// **The shield goes up on the way out, always.** `paused` fires before the app appears in the
/// task switcher, so the cover is already painted over the content in the snapshot the OS takes.
/// That costs nothing and is not a prompt.
///
/// **The prompt only fires if the app has been away longer than [kBiometricGrace].** Within the
/// window the shield simply lifts. Cold start honours the same rule through a persisted
/// timestamp, so force-quitting and reopening is not a way to be asked more often, and the app
/// restarting itself in the background is not a way to be asked at all.
class BiometricLock extends ConsumerStatefulWidget {
  const BiometricLock({
    super.key,
    required this.enabled,
    required this.child,
    this.grace = kBiometricGrace,
    this.store = const SecureLockActivityStore(),
  });

  /// The Impostazioni setting. False means this widget is a pass-through.
  final bool enabled;

  final Widget child;

  /// How long the app may be backgrounded before the next return needs a prompt.
  final Duration grace;

  /// Where "last in use" is recorded. Injected in tests.
  final LockActivityStore store;

  @override
  ConsumerState<BiometricLock> createState() => _BiometricLockState();
}

class _BiometricLockState extends ConsumerState<BiometricLock> with WidgetsBindingObserver {
  /// Needs a successful prompt before the content is usable.
  bool _locked = false;

  /// Covered because the app is in the background, with no prompt owed. Lifts on its own.
  bool _shielded = false;

  bool _prompting = false;
  DateTime? _lastRefreshAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) {
      // Cover first, decide after. Reading the timestamp is async, and an uncovered frame while
      // that happens would show the data the lock exists to hide.
      _locked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resumeFromColdStart());
    }
  }

  @override
  void didUpdateWidget(BiometricLock old) {
    super.didUpdateWidget(old);
    // Switched on in Settings: take effect now, not at the next cold start. No prompt — the
    // setting screen has just verified this person's fingerprint to let them turn it on.
    if (widget.enabled && !old.enabled) {
      _markActive();
    } else if (!widget.enabled && old.enabled) {
      setState(() {
        _locked = false;
        _shielded = false;
      });
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

    // Cover on `inactive`, not on `paused`.
    //
    // By the time `paused` arrives the framework has stopped producing frames, so a cover raised
    // there is never painted — the snapshot the OS keeps for the task switcher is still the
    // content underneath. `inactive` fires while the app is still drawing and before it is
    // obscured, which is the last moment the cover can actually reach the screen.
    //
    // It also fires for transient interruptions — the notification shade, a permission sheet,
    // the biometric prompt itself. Covering for those is the right answer anyway: it is a cover,
    // not a prompt, and it lifts on its own the moment the app is back.
    if (!_prompting &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      if (!_shielded) setState(() => _shielded = true);
      // Only stamp on the way fully out. `inactive` fires on every glance at the shade, and
      // stamping there would keep pushing the grace window forward without the app being used.
      if (state == AppLifecycleState.paused) _markActive();
    } else if (state == AppLifecycleState.resumed && !_prompting) {
      _resumeFromBackground();
    }
  }

  /// Records "the app was in the technician's hands at this moment".
  ///
  /// Written when the app goes to the background and again on every successful unlock, so the
  /// grace window measures time away rather than time since the last prompt.
  Future<void> _markActive() => widget.store.markActive(DateTime.now());

  Future<bool> _withinGrace() async {
    final last = await widget.store.lastActiveAt();
    if (last == null) return false;
    final elapsed = DateTime.now().difference(last);
    // A negative elapsed means the clock moved backwards — treat that as expired rather than as
    // an unbounded grace period, because winding the clock back would otherwise open the app.
    return !elapsed.isNegative && elapsed < widget.grace;
  }

  Future<void> _resumeFromColdStart() async {
    if (await _withinGrace()) {
      if (!mounted) return;
      setState(() => _locked = false);
      await _refreshSession(force: true);
      return;
    }
    await _prompt();
  }

  Future<void> _resumeFromBackground() async {
    if (await _withinGrace()) {
      if (!mounted) return;
      setState(() {
        _shielded = false;
        _locked = false;
      });
      await _refreshSession();
      return;
    }
    if (!mounted) return;
    setState(() => _locked = true);
    await _prompt();
  }

  /// Gets the session usable again, rather than waiting for a request to bounce off a 401.
  ///
  /// The access token has a short life and the app is frequently away for longer than it. Coming
  /// back to a screen that renders, then stalls on its first fetch while the interceptor
  /// discovers the token is dead and refreshes it, reads as the app being slow. Doing it here
  /// means the first tap after unlocking hits a live session.
  ///
  /// Failure is deliberately silent: offline is the normal condition in a plant room, the cached
  /// data is still readable, and `AuthInterceptor` and `AuthReconnectWatcher` both retry later.
  Future<void> _refreshSession({bool force = false}) async {
    final last = _lastRefreshAt;
    if (!force && last != null && DateTime.now().difference(last) < _kSessionRefreshAfter) {
      return;
    }
    _lastRefreshAt = DateTime.now();
    try {
      await ref.read(authRepositoryProvider).refreshSession();
    } catch (_) {
      // Nothing to tell the technician: they did not ask for this and cannot act on it.
    }
  }

  Future<void> _prompt() async {
    if (_prompting) return;
    _prompting = true;
    try {
      final ok = await ref
          .read(biometricServiceProvider)
          .authenticate(reason: 'Sblocca TaskTap per accedere ai dati di clienti e interventi');
      if (!mounted) return;
      if (ok) {
        setState(() {
          _locked = false;
          _shielded = false;
        });
        await _markActive();
        await _refreshSession(force: true);
      }
    } finally {
      _prompting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !(_locked || _shielded)) return widget.child;

    // The child stays in the tree beneath the cover so its state — a running timer, a half-written
    // rapportino — survives being locked. It is covered, not disposed.
    return Stack(
      children: [
        widget.child,
        Positioned.fill(child: _LockScreen(showPrompt: _locked)),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.showPrompt});

  /// False while the app is merely covered for the task switcher. There is nothing for the
  /// technician to do in that state and it is gone before they see it, so it carries no copy and
  /// no button — a "Sblocca" that flashes past on every app switch is noise.
  final bool showPrompt;

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
            child: showPrompt
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.fingerprint, size: 40, color: AppVetroColors.tint),
                      const SizedBox(height: 20),
                      const Text(
                        'TaskTap è bloccato',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sblocca con impronta o Face ID per accedere ai dati di clienti e '
                        'interventi.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
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
                          // A retry, because the OS prompt can be dismissed and a lock with no
                          // way back in is a lock-out.
                          onPressed: () =>
                              context.findAncestorStateOfType<_BiometricLockState>()?._prompt(),
                        ),
                      ),
                    ],
                  )
                : const Icon(LucideIcons.fingerprint, size: 40, color: AppVetroColors.tint),
          ),
        ),
      ),
    );
  }
}
