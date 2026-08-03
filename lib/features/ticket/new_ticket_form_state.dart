// dart format width=100

// ══════════════════════════════════════════════════════════════════════════════
// NewTicketFormState
//
// Immutable form state for the multi-step new ticket form.
// Extracted to its own file to allow unit testing without pulling in
// widget dependencies (LucideIcons etc.).
// ══════════════════════════════════════════════════════════════════════════════

class NewTicketFormState {
  const NewTicketFormState({
    this.customerId,
    this.locationId,
    this.title,
    this.description,
    this.typeId,
    this.statusId,
    this.assignedUserId,
  });

  final String? customerId;
  final String? locationId;
  final String? title;
  final String? description;
  final int? typeId;
  final int? statusId;
  final String? assignedUserId;

  NewTicketFormState copyWith({
    String? customerId,
    String? locationId,
    String? title,
    String? description,
    int? typeId,
    int? statusId,
    String? assignedUserId,
    bool clearCustomerId = false,
    bool clearLocationId = false,
    bool clearTitle = false,
    bool clearDescription = false,
    bool clearTypeId = false,
    bool clearStatusId = false,
    bool clearAssignedUserId = false,
  }) {
    return NewTicketFormState(
      customerId: clearCustomerId ? null : (customerId ?? this.customerId),
      locationId: clearLocationId ? null : (locationId ?? this.locationId),
      title: clearTitle ? null : (title ?? this.title),
      description: clearDescription ? null : (description ?? this.description),
      typeId: clearTypeId ? null : (typeId ?? this.typeId),
      statusId: clearStatusId ? null : (statusId ?? this.statusId),
      assignedUserId:
          clearAssignedUserId ? null : (assignedUserId ?? this.assignedUserId),
    );
  }

  bool get isValid =>
      customerId != null &&
      locationId != null &&
      title != null &&
      title!.trim().isNotEmpty &&
      typeId != null &&
      statusId != null;
}
