// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

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
// "submitting" state. If offline, it shows a clear SnackBar and returns
// false — the caller must return immediately without touching the network
// or clearing the form. Text fields already keep their contents (nothing
// clears them on failure), so refusing to even attempt offline is what
// turns a confusing generic Dio error into an honest, actionable message.
// ══════════════════════════════════════════════════════════════════════════════

bool ensureOnlineOrWarn(BuildContext context, WidgetRef ref) {
  final isOnline = ref.read(isOnlineProvider);
  if (isOnline) return true;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Sei offline: impossibile salvare in questo momento. '
        'I dati inseriti restano nel modulo: riprova quando torni online.',
      ),
      backgroundColor: context.colors.red,
    ),
  );
  return false;
}
