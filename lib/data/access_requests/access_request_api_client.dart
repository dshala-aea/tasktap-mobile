import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dio_client.dart';

const int kAccessRequestMaxEmailLength = 254;
const int kAccessRequestMaxNameLength = 120;
const int kAccessRequestMaxCompanyLength = 160;
const int kAccessRequestMaxPhoneLength = 40;
const int kAccessRequestMaxMessageLength = 2000;

class AccessRequestApiClient {
  AccessRequestApiClient(this._dio);

  final Dio _dio;

  Future<void> submit({
    required String email,
    String? name,
    String? company,
    String? phone,
    String? message,
  }) async {
    final body = <String, dynamic>{'email': email.trim()};

    void addIfPresent(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) body[key] = trimmed;
    }

    addIfPresent('name', name);
    addIfPresent('company', company);
    addIfPresent('phone', phone);
    addIfPresent('message', message);

    await _dio.post<void>('/api/access-requests', data: body);
  }
}

final accessRequestApiClientProvider = Provider<AccessRequestApiClient>(
  (ref) => AccessRequestApiClient(ref.watch(dioProvider)),
);
