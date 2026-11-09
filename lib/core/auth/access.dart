// dart format width=100
import '../../data/entitlements/entitlement_repository.dart';

/// The shared refusal copy for an action the signed-in seat does not hold.
const String noPermissionReason = 'Non hai i permessi per questa azione.';

/// The shared refusal copy for an action reserved to an office (or admin) seat.
const String officeOnlyReason = 'Solo ufficio o amministrazione.';

/// Whether [entitlement] holds [capability]. Fail-closed: nothing cached means denied, matching
/// [EntitlementRepository.hasCapability] and the route guard's capability rule.
bool capabilityHeld(Entitlement? entitlement, String capability) =>
    entitlement?.capabilities.contains(capability) ?? false;

/// Whether the signed-in seat is an office seat. Null means unknown, so this is false rather than
/// an assumption about what may be shown — callers use it only to *withhold* office-only actions.
bool isOfficeSeat(Entitlement? entitlement) => entitlement?.seatType == 'office';
