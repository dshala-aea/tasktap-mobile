// dart format width=100

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The address the technician confirmed for the customer's copy of a signed rapportino
/// (ClickUp 12493t4wxvm), kept per local draft until the submit carries it to the server.
///
/// SharedPreferences rather than a `DraftReports` column on purpose: a Drift column needs a schema
/// migration (and its fixtures) for a value that only lives between "the customer signed" and "the
/// submit reached the server". If it ever has to outlive that — shown on a submitted report, say —
/// promote it to a column then. Like every other preference it is wiped with sign-out.
///
/// Absent = the technician has not decided (the screen pre-fills the customer's email); an empty
/// string = "do not send a copy"; anything else is the address to send to. Not cleared after the
/// submit (a few bytes per report); wiped with the other preferences at sign-out.
class CustomerCopyRecipientStore {
  CustomerCopyRecipientStore({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  static String _key(String reportId) => 'customer_copy.recipient.$reportId';

  /// The stored decision: null (none yet), '' (no copy), or the address.
  Future<String?> read(String reportId) async => (await _prefs()).getString(_key(reportId));

  Future<void> write(String reportId, String recipient) async {
    await (await _prefs()).setString(_key(reportId), recipient.trim());
  }

  /// What `SubmitReportRequest.customerCopyRecipient` must carry: the address, or null when the
  /// technician chose not to send (or never decided — the server then sends nothing).
  Future<String?> recipientForSubmit(String reportId) async {
    final v = (await read(reportId))?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}

final customerCopyRecipientStoreProvider = Provider<CustomerCopyRecipientStore>(
  (ref) => CustomerCopyRecipientStore(),
);
