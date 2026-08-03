import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dio_client.dart';

class TicketApiClient {
  TicketApiClient(this._dio);

  final Dio _dio;

  Future<String> createTicket({
    required String title,
    String? description,
    required String customerId,
    required String locationId,
    String? assignedUserId,
    required int statusId,
    required int typeId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/tickets',
      data: {
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        'customerId': customerId,
        'locationId': locationId,
        if (assignedUserId != null) 'assignedUserId': assignedUserId,
        'statusId': statusId,
        'typeId': typeId,
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
