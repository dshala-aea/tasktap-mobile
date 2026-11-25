import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Response header the API sets when this build is below the minimum but the call was let
/// through (an allow-listed queue-flush endpoint).
const updateRequiredHeader = 'x-app-update-required';

/// Response header the API sets when this build is below the recommended one (soft nudge).
const updateAvailableHeader = 'x-app-update-available';

/// `code` of the flat problem+json body on a blocked call (HTTP 426).
const appUpdateRequiredCode = 'app_update_required';

/// True once the server has said this build is too old. Never goes back to false in a session:
/// only installing a newer build clears it. Whether to *show* the blocking screen is a separate
/// decision (it waits until the offline queues are empty); this only records the fact.
class UpdateRequiredNotifier extends StateNotifier<bool> {
  UpdateRequiredNotifier() : super(false);

  void markRequired() {
    if (!state) state = true;
  }

  /// Lowers the state, for a policy refresh that finds the server no longer requires an update.
  void clear() {
    if (state) state = false;
  }
}

final updateRequiredProvider =
    StateNotifierProvider<UpdateRequiredNotifier, bool>(
      (ref) => UpdateRequiredNotifier(),
    );

/// True once the server has said a newer build is recommended (not required).
class UpdateAvailableNotifier extends StateNotifier<bool> {
  UpdateAvailableNotifier() : super(false);

  void markAvailable() {
    if (!state) state = true;
  }

  void clear() {
    if (state) state = false;
  }
}

final updateAvailableProvider =
    StateNotifierProvider<UpdateAvailableNotifier, bool>(
      (ref) => UpdateAvailableNotifier(),
    );

/// True when [response] carries `X-App-Update-Required: true` (header names are case-insensitive).
bool hasUpdateRequiredHeader(Response<dynamic> response) =>
    response.headers.value(updateRequiredHeader)?.toLowerCase() == 'true';

/// True when [response] carries `X-App-Update-Available: true`.
bool hasUpdateAvailableHeader(Response<dynamic> response) =>
    response.headers.value(updateAvailableHeader)?.toLowerCase() == 'true';

/// True when [response] is the server's "update the app" answer: HTTP 426 whose body names the
/// `app_update_required` code; a body that cannot be read (bytes/stream response types) is
/// accepted on the status alone.
bool isUpdateRequiredResponse(Response<dynamic>? response) {
  if (response == null || response.statusCode != 426) return false;
  var body = response.data;
  try {
    if (body is List<int>) body = utf8.decode(body, allowMalformed: true);
    if (body is String) body = jsonDecode(body);
  } catch (_) {
    // Readable text that is not our JSON (a proxy's plain-text 426): not the update answer.
    return false;
  }
  if (body is Map) return body['code'] == appUpdateRequiredCode;
  // Stream bodies (ResponseType.stream) and other unreadable shapes: the API is the only 426
  // source this app talks to, so the status alone is taken as the update-required answer.
  return true;
}

/// True when [error] is a [DioException] carrying the update-required answer. For the offline
/// queues: such a failure means "this build may not talk to the server yet", not "this item is
/// bad", so the item must stay queued with no attempt consumed.
bool isUpdateRequiredError(Object? error) =>
    error is DioException && isUpdateRequiredResponse(error.response);
