// dart format width=100
// ══════════════════════════════════════════════════════════════════════════════
// CustomerContactApiClient
//
// Thin Dio wrapper for a customer's labeled contacts —
//   GET    /api/customers/{customerId}/contacts
//   POST   /api/customers/{customerId}/contacts
//   PUT    /api/customers/{customerId}/contacts/{contactId}
//   DELETE /api/customers/{customerId}/contacts/{contactId}
//
// Mirrors `CustomersController`'s Contacts endpoints (backend `CustomerContact` entity,
// `UpsertCustomerContactRequest`) and follows the style of `ClienteOverviewApiClient` /
// `CantiereWorklogApiClient` — a small hand-written client and a plain Dart model with
// `fromJson`, no codegen. `name` is the only required field; `role`/`phone`/`email`/`notes` are
// all optional.
//
// Distinct from the single flat `contactPerson` string already on `Customer`
// (admin_customer_form_screen.dart's `_contactPersonCtrl`) — this is a list of labeled contacts,
// a separate concept, not a replacement for that field.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

/// One labeled contact for a customer (`CustomerContact`, backend entity).
class CustomerContact {
  const CustomerContact({
    required this.id,
    required this.customerId,
    required this.name,
    this.role,
    this.phone,
    this.email,
    this.notes,
  });

  final String id;
  final String customerId;
  final String name;
  final String? role;
  final String? phone;
  final String? email;
  final String? notes;

  factory CustomerContact.fromJson(Map<String, dynamic> json) => CustomerContact(
    id: json['id'] as String? ?? '',
    customerId: json['customerId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    role: json['role'] as String?,
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    notes: json['notes'] as String?,
  );
}

class CustomerContactApiClient {
  CustomerContactApiClient(this._dio);

  final Dio _dio;

  /// `GET /api/customers/{customerId}/contacts` — a bare array, no pagination envelope
  /// (`CustomersController.GetContacts` returns `Ok(contacts)` directly).
  Future<List<CustomerContact>> list(String customerId) async {
    final response = await _dio.get<List<dynamic>>('/api/customers/$customerId/contacts');
    final data = response.data ?? [];
    return data.cast<Map<String, dynamic>>().map(CustomerContact.fromJson).toList();
  }

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
