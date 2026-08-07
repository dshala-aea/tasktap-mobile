import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dio_client.dart';

class TicketApiClient {
  TicketApiClient(this._dio);

  final Dio _dio;

  /// Creates a ticket, returning its server id.
  ///
  /// [clientId] is the local row's own uuid, carried so the server can recognise a resend. It
  /// answers 200 with the ticket it already created instead of 201 with a second one, so a retry
  /// after a lost reply is safe. Both statuses carry the same body and mean the same thing here:
  /// this ticket exists on the server with this id.
  Future<String> createTicket({
    required String title,
    String? description,
    required String customerId,
    required String locationId,
    String? assignedUserId,
    required int statusId,
    required int typeId,
    String? clientId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/tickets',
      data: {
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        'customerId': customerId,
        'locationId': locationId,
        'assignedUserId': ?assignedUserId,
        'statusId': statusId,
        'typeId': typeId,
        'clientId': ?clientId,
      },
    );

    return response.data!['ticketId'] as String;
  }

  Future<List<Map<String, dynamic>>> fetchTechnicians() async {
    final response = await _dio.get<List<dynamic>>(
      '/api/users',
      queryParameters: {'role': 'Technician', 'isActive': 'true'},
    );

    return (response.data ?? []).cast<Map<String, dynamic>>();
  }
}

final ticketApiClientProvider = Provider<TicketApiClient>((ref) {
  return TicketApiClient(ref.watch(dioProvider));
});
