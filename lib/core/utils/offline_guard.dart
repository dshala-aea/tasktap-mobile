// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entitlements/entitlement_providers.dart';
import '../../data/sync/connectivity_provider.dart';
import '../widgets/widgets.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ensureOnlineOrWarn
//
// Admin forms (customers, locations, schedules, contracts, squadre, prodotti,
// materiali, cantieri) write straight to the backend with no local queue —
// queuing them was judged not worth the risk (a wrong queue is worse than an
// honest error). The minimum bar is: never discard what the technician typed,
// and say plainly why the save didn't happen.
//
// Call this at the top of a form's submit handler, before setting any
// "submitting" state. If offline, it shows a clear toast and returns
// false — the caller must return immediately without touching the network
// or clearing the form. Text fields already keep their contents (nothing
// clears them on failure), so refusing to even attempt offline is what
// turns a confusing generic Dio error into an honest, actionable message.
//
// Also checks subscription state, for the same reason: a suspended tenant's
// writes 403 server-side (EntitlementMiddleware gates writes, not reads — see
// SuspendedBanner, which warns proactively; this is the reactive half for the
// moment someone actually presses save). Checked after connectivity, since an
// offline device may be showing a stale cached entitlement — "you're offline"
// is the truer answer when both are true.
// ══════════════════════════════════════════════════════════════════════════════

bool ensureOnlineOrWarn(BuildContext context, WidgetRef ref) {
  final isOnline = ref.read(isOnlineProvider);
  if (!isOnline) {
    showAppToast(
      context,
      message:
          'Sei offline: impossibile salvare in questo momento. '
          'I dati inseriti restano nel modulo: riprova quando torni online.',
      tone: ToastTone.error,
    );
    return false;
  }

  final entitlement = ref.read(cachedEntitlementProvider).value;
  if (entitlement != null && entitlement.isSuspended) {
    showAppToast(
      context,
      message:
          'Abbonamento non attivo: impossibile salvare finché non viene riattivato. '
          'I dati inseriti restano nel modulo.',
      tone: ToastTone.error,
    );
    return false;
  }

  return true;
}
