// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CustomerContactApiClient
//
// Thin Dio wrapper for the WRITE half of a customer's labeled contacts —
//   POST   /api/customers/{customerId}/contacts
//   PUT    /api/customers/{customerId}/contacts/{contactId}
//   DELETE /api/customers/{customerId}/contacts/{contactId}
//
// Not the read half: `GET /api/customers/{customerId}/contacts` used to live here, but the list now
// renders from the Drift mirror the sync fills (`customerContactsProvider`), so a device-side read
// would be a second, diverging answer to the same question. The office owns these rows; the device
// only writes.
//
// Mirrors `CustomersController`'s Contacts endpoints (backend `CustomerContact` entity,
// `UpsertCustomerContactRequest`) and follows the style of `ClienteOverviewApiClient` /
// `CantiereWorklogApiClient` — a small hand-written client, no codegen. `name` is the only required
// field; `role`/`phone`/`email`/`notes` are all optional.
//
// Distinct from the single flat `contactPerson` string already on `Customer`
// (admin_customer_form_screen.dart's `_contactPersonCtrl`) — this is a list of labeled contacts,
// a separate concept, not a replacement for that field.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

class CustomerContactApiClient {
  CustomerContactApiClient(this._dio);

  final Dio _dio;

  /// `POST /api/customers/{customerId}/contacts` — returns the new contact's id
  /// (`BasicPkResponse`).
  Future<String> create(
    String customerId, {
    required String name,
    String? role,
    String? phone,
    String? email,
    String? notes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/customers/$customerId/contacts',
      data: {
        'name': name,
        if (role != null && role.isNotEmpty) 'role': role,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return response.data!['id'] as String;
  }

  /// `PUT /api/customers/{customerId}/contacts/{contactId}`.
  Future<void> update(
    String customerId,
    String contactId, {
    required String name,
    String? role,
    String? phone,
    String? email,
    String? notes,
  }) async {
    await _dio.put(
      '/api/customers/$customerId/contacts/$contactId',
      data: {
        'name': name,
        if (role != null && role.isNotEmpty) 'role': role,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
  }

  /// `DELETE /api/customers/{customerId}/contacts/{contactId}`.
  Future<void> delete(String customerId, String contactId) async {
    await _dio.delete('/api/customers/$customerId/contacts/$contactId');
  }
}

final customerContactApiClientProvider = Provider<CustomerContactApiClient>((ref) {
  return CustomerContactApiClient(ref.watch(dioProvider));
});
