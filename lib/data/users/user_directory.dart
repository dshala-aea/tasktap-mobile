// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/admin/admin_api_client.dart';

/// The display name for a `/api/users` row.
///
/// The payload carries no guaranteed `displayName`: the server's own `fullName` is preferred, then
/// the name parts. A row with none of them is still a valid user (and a valid member), so it gets
/// a neutral label rather than the raw id or an email.
String userDisplayName(Map<String, dynamic> user) {
  final display = (user['displayName'] as String?)?.trim();
  if (display != null && display.isNotEmpty) return display;

  final full = (user['fullName'] as String?)?.trim();
  if (full != null && full.isNotEmpty) return full;

  final first = (user['firstName'] as String? ?? '').trim();
  final last = (user['lastName'] as String? ?? '').trim();
  final composed = '$first $last'.trim();
  if (composed.isNotEmpty) return composed;

  return 'Utente senza nome';
}

/// Every user in the tenant, keyed by whether inactive users are included.
///
/// Shared by the squadra screens (which count active members) and the approval queues (which must
/// still name a requester who has since left). One bulk fetch per call; the API paginates.
final allUsersProvider = FutureProvider.family.autoDispose<List<Map<String, dynamic>>, bool>((
  ref,
  activeOnly,
) {
  final api = ref.watch(adminApiClientProvider);
  return api.fetchAllUsersWithSquadraInfo(activeOnly: activeOnly);
});

/// Id → display name for the approval queues.
///
/// Names are decorative: an approver without `team.user.read`, or an offline device, still gets a
/// usable queue. Any lookup failure resolves to an empty map, and the screen renders `—` for the
/// unknown ids — never a raw GUID. Inactive users are included so a pending request filed by
/// someone who has since left still carries a name.
final userNameByIdProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  try {
    final users = await ref.watch(allUsersProvider(false).future);
    final byId = <String, String>{};
    for (final user in users) {
      final id = user['id'];
      if (id is String && id.isNotEmpty) byId[id] = userDisplayName(user);
    }
    return byId;
  } catch (_) {
    return const {};
  }
});
