// dart format width=100
import 'package:dio/dio.dart';

// ══════════════════════════════════════════════════════════════════════════════
// NotificationApiClient
//
// Thin Dio wrapper for the notification endpoints:
//   GET    /api/notifications          — paginated list (InApp delivery only)
//   PUT    /api/notifications/{id}/read — mark one as read
//   PUT    /api/notifications/read-all  — mark all as read
//
// No client for GET /api/notifications/unread-count: the app derives its badge count from the
// Drift-cached notification list instead (notificheUnreadCountProvider), which stays correct
// offline and needs no extra round trip. A dedicated method for this route existed here with zero
// callers and was removed rather than kept as unused surface.
// ══════════════════════════════════════════════════════════════════════════════

class NotificationApiClient {
  NotificationApiClient(this._dio);

  final Dio _dio;

  /// Fetch the current user's notifications (InApp delivery type).
  ///
  /// Returns a paginated list. The backend defaults to page=1, pageSize=20.
  /// [isRead] — filter by read status (null = all).
  /// [page] — 1-indexed page number.
  /// [pageSize] — items per page (max 50).
  Future<NotificationPageResponse> getNotifications({
    bool? isRead,
    int page = 1,
    int pageSize = 20,
  }) async {
    final queryParams = <String, dynamic>{
      'page': page,
      'pageSize': pageSize,
      'deliveryType': 0, // InApp = 0 (NotificationDeliveryTypeEnum)
    };
    if (isRead != null) queryParams['isRead'] = isRead;

    final response = await _dio.get('/api/notifications', queryParameters: queryParams);

    return NotificationPageResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Mark a single notification as read.
  Future<void> markAsRead(String notificationId) async {
    await _dio.put('/api/notifications/$notificationId/read');
  }

  /// Mark all notifications as read for the current user.
  Future<void> markAllAsRead() async {
    await _dio.put('/api/notifications/read-all');
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DTOs
// ══════════════════════════════════════════════════════════════════════════════

class NotificationPageResponse {
  NotificationPageResponse({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalItems,
    required this.totalPages,
    required this.unreadCount,
  });

  factory NotificationPageResponse.fromJson(Map<String, dynamic> json) {
    return NotificationPageResponse(
      items: (json['items'] as List)
          .map((e) => NotificationDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: json['page'] as int,
      pageSize: json['pageSize'] as int,
      totalItems: json['totalItems'] as int,
      totalPages: json['totalPages'] as int,
      unreadCount: json['unreadCount'] as int,
    );
  }

  final List<NotificationDto> items;
  final int page;
  final int pageSize;
  final int totalItems;
  final int totalPages;
  final int unreadCount;
}

class NotificationDto {
  NotificationDto({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.type,
    required this.deliveryType,
    required this.isRead,
    this.readAt,
    this.relatedEntityId,
    this.relatedEntityType,
    this.scheduledFor,
    this.sentAt,
    required this.isDelivered,
    required this.createdAt,
  });

  factory NotificationDto.fromJson(Map<String, dynamic> json) {
    return NotificationDto(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      type: json['type'] as String,
      deliveryType: json['deliveryType'] as String,
      isRead: json['isRead'] as bool,
      readAt: json['readAt'] as String?,
      relatedEntityId: json['relatedEntityId'] as String?,
      relatedEntityType: json['relatedEntityType'] as String?,
      scheduledFor: json['scheduledFor'] as String?,
      sentAt: json['sentAt'] as String?,
      isDelivered: json['isDelivered'] as bool,
      createdAt: json['createdAt'] as String,
    );
  }

  final String id;
  final String userId;
  final String title;
  final String message;
  final String type;
  final String deliveryType;
  final bool isRead;
  final String? readAt;
  final String? relatedEntityId;
  final String? relatedEntityType;
  final String? scheduledFor;
  final String? sentAt;
  final bool isDelivered;
  final String createdAt;
}
