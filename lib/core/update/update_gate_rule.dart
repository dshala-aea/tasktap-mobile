// dart format width=100
/// What the app shell shows for the version gate.
enum UpdateGateMode {
  /// Nothing about updates is forced.
  none,

  /// An update is required but the phone still holds unsent work: calm "Sincronizza, poi aggiorna"
  /// banner, the app stays usable and the queues keep flushing.
  syncFirst,

  /// An update is required and nothing is waiting to be sent: blocking screen.
  blocked,
}

/// The gate rule: block only when an update is required AND the pending-sync count is known to be
/// zero. [pending] is null while the count is still loading or unreadable; an unknown count never
/// blocks (the server still answers 426, and the queues keep their items).
UpdateGateMode updateGateMode({required bool updateRequired, required int? pending}) {
  if (!updateRequired || pending == null) return UpdateGateMode.none;
  return pending > 0 ? UpdateGateMode.syncFirst : UpdateGateMode.blocked;
}
