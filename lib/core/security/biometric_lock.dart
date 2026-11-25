// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../domain/auth/auth_user.dart';
import '../../presentation/providers/auth_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
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

/// How long a cold start waits for the stored session to be restored (or found absent) before it
/// decides from what is known. The restore is bounded on its own side; this is only a backstop.
const Duration _kSessionWait = Duration(seconds: 30);

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
///
/// The lock only ever applies when it can be passed: it never shows without a signed-in session
/// (login screen, after logout: there is nothing to protect) and never on a device that no longer
/// has an enrolled biometric (the setting may outlive the enrolment; failing closed there would
/// be a permanent lock-out). Both checks are local: no network is involved in deciding.
///
/// Z-order: this widget wraps [UpdateGate] in `main.dart`, so the lock sits above everything,
/// including the update-required screen, which stays covered until the technician unlocks. That is
/// deliberate: the lock is local and instant, the store button is one fingerprint away, and
/// putting the gate above the lock would let an out-of-date build bypass the lock entirely.
class BiometricLock extends ConsumerStatefulWidget {
  const BiometricLock({
    super.key,
    required this.enabled,
    required this.child,
    this.grace = kBiometricGrace,
    this.store = const SecureLockActivityStore(),
    this.clock = DateTime.now,
    this.sessionWait = _kSessionWait,
  });

  /// The Impostazioni setting. False means this widget is a pass-through.
  final bool enabled;

  final Widget child;

  /// How long the app may be backgrounded before the next return needs a prompt.
  final Duration grace;

  /// Where "last in use" is recorded. Injected in tests.
  final LockActivityStore store;

  /// The time source for the grace window. Injected in tests.
  final DateTime Function() clock;

  /// How long the cold start waits for the stored session to be restored before deciding. Injected
  /// in tests; a restore that lands later still arms the lock (see `_coldStartDecided`).
  final Duration sessionWait;

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

  /// True once the cold-start decision (lock / grace / nothing to protect) was taken on a settled
  /// answer. A decision cut short by [_kSessionWait] expiring with no session is NOT final: the
  /// restore may still land, and when it does the decision is re-run (see the auth listener), so a
  /// slow restore can never leave the app open without its lock.
  bool _coldStartDecided = false;

  /// Set by [_hasSession] when the bounded wait ran out with no session visible.
  bool _sessionWaitTimedOut = false;

  /// Whether the device can currently prompt. Null until first checked; null is treated as
  /// "assume yes" for the cheap shield only, never for the prompt.
  bool? _available;

  bool get _hasSessionNow => ref.read(authRepositoryProvider).currentUser != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) {
      // Cover first, decide after. Reading the timestamp is async, and an uncovered frame while
      // that happens would show the data the lock exists to hide.
      // A shield, not yet a lock: whether anything needs locking (session, enrolment) is decided
      // after the first frame, and an uncovered frame in between is not acceptable.
      _shielded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resumeFromColdStart());
    }
    // A session that ends (logout, forced sign-out) leaves nothing to protect: drop the cover so
    // the login screen is never held behind it.
    ref.listenManual(authStateProvider, (previous, next) {
      if (next is AsyncData<AuthUser?> && next.value == null) _release();
      // The restore finished after the cold-start wait gave up (worst case ~22 s): decide now.
      if (next is AsyncData<AuthUser?> &&
          next.value != null &&
          widget.enabled &&
          !_coldStartDecided &&
          !_locked &&
          !_shielded) {
        setState(() => _shielded = true);
        unawaited(_resumeFromColdStart());
      }
    });
  }

  /// Back button while the cover is up. The lock sits above the Navigator, so there is no
  /// ModalRoute and PopScope is inert here; the observer is the only place a back press can be
  /// swallowed before the Router pops the hidden stack.
  @override
  Future<bool> didPopRoute() async => widget.enabled && (_locked || _shielded);

  void _release() {
    if (!mounted || !(_locked || _shielded)) return;
    setState(() {
      _locked = false;
      _shielded = false;
    });
  }

  /// Local-only: a stored session exists and the device can still prompt.
  Future<bool> _lockApplies() async {
    final hasSession = await _hasSession();
    // Riverpod 3 throws on `ref.read` after dispose, and the wait above can be long.
    if (!mounted || !hasSession) return false;
    bool available;
    try {
      available = await ref.read(biometricServiceProvider).isAvailable();
    } catch (_) {
      available = false;
    }
    _available = available;
    return available;
  }

  Future<bool> _hasSession() async {
    final repo = ref.read(authRepositoryProvider);
    if (repo.currentUser != null) return true;
    // Cold start: the stored session is restored asynchronously, so "no user yet" is not "no
    // session". Wait for the auth state to resolve, bounded.
    _sessionWaitTimedOut = false;
    try {
      final user = await ref.read(authStateProvider.future).timeout(widget.sessionWait);
      return user != null || repo.currentUser != null;
    } catch (_) {
      final has = repo.currentUser != null;
      _sessionWaitTimedOut = !has;
      return has;
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
        _hasSessionNow &&
        _available != false &&
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
  Future<void> _markActive() => widget.store.markActive(widget.clock());

  Future<bool> _withinGrace() async {
    final last = await widget.store.lastActiveAt();
    if (last == null) return false;
    final elapsed = widget.clock().difference(last);
    // A negative elapsed means the clock moved backwards — treat that as expired rather than as
    // an unbounded grace period, because winding the clock back would otherwise open the app.
    return !elapsed.isNegative && elapsed < widget.grace;
  }

  Future<void> _resumeFromColdStart() async {
    final applies = await _lockApplies();
    if (!mounted) return;
    // Final unless the wait merely ran out (see [_coldStartDecided]).
    if (applies || !_sessionWaitTimedOut) _coldStartDecided = true;
    if (!applies) {
      _release();
      return;
    }
    if (await _withinGrace()) {
      if (!mounted) return;
      _release();
      await _refreshSession(force: true);
      return;
    }
    if (!mounted) return;
    setState(() => _locked = true);
    await _prompt();
  }

  Future<void> _resumeFromBackground() async {
    // Resume is synchronous about the session (already restored by now) and re-checks enrolment,
    // which can change while the app is away.
    if (!_hasSessionNow || !await _lockApplies()) {
      // While the cold-start decision is still pending the cover stays: the auth listener decides.
      if (_coldStartDecided) _release();
      return;
    }
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
    if (!force && last != null && widget.clock().difference(last) < _kSessionRefreshAfter) {
      return;
    }
    _lastRefreshAt = widget.clock();
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
    } catch (_) {
      // The prompt itself failed (platform error): stay locked, the technician can tap again.
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
    // Its own Material: this sits above the Navigator (MaterialApp `builder`), so there is no
    // ancestor Material/Overlay to lean on, and text would otherwise lose the default text style.
    return Material(
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
                      Icon(LucideIcons.fingerprint, size: 40, color: context.colors.accent),
                      const SizedBox(height: 20),
                      const Text(
                        'TaskTap è bloccato',
                        style: TextStyle(
                          fontFamily: 'Archivo Narrow',
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
                          fontFamily: 'Archivo',
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
                : Icon(LucideIcons.fingerprint, size: 40, color: context.colors.accent),
          ),
        ),
      ),
    );
  }
}
