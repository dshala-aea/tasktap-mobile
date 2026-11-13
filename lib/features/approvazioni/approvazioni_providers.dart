// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ferie/absence_request_api_client.dart';
import '../../data/smart_working/smart_working_request_api_client.dart';

/// The tenant-wide pending absence requests — the approver's worklist.
///
/// Online-only: there is no local mirror of other people's requests, and a stale queue must not be
/// presented as the current one. A failed read throws; the screen shows the error/offline state. A
/// decision invalidates this provider and the caller's own list.
final absenceApprovalQueueProvider = FutureProvider.autoDispose<List<AbsenceRequestDto>>((ref) {
  return ref.watch(absenceRequestApiClientProvider).fetchPendingForApproval();
});

/// The tenant-wide pending smart-working requests — the same worklist for the other entity.
final smartWorkingApprovalQueueProvider = FutureProvider.autoDispose<List<SmartWorkingRequestDto>>((
  ref,
) {
  return ref.watch(smartWorkingRequestApiClientProvider).fetchPendingForApproval();
});
