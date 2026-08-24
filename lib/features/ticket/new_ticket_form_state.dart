// dart format width=100

// ══════════════════════════════════════════════════════════════════════════════
// NewTicketFormState
//
// Immutable form state for the multi-step new ticket form.
// Extracted to its own file to allow unit testing without pulling in
// widget dependencies (LucideIcons etc.).
// ══════════════════════════════════════════════════════════════════════════════

/// TicketPriorityEnum values (TicketPriorityEnum.cs) — sent on the wire as `priorita`, a
/// string, not an int. "Media" is the backend's own default.
const List<String> kTicketPriorities = ['Bassa', 'Media', 'Alta', 'Urgente'];
const String kDefaultTicketPriority = 'Media';

class NewTicketFormState {
  const NewTicketFormState({
    this.customerId,
    this.locationId,
    this.title,
    this.description,
    this.typeId,
    this.statusId,
    this.assignedUserId,
    this.priority = kDefaultTicketPriority,
  });

  final String? customerId;
  final String? locationId;
  final String? title;
  final String? description;
  final int? typeId;
  final int? statusId;
  final String? assignedUserId;

  /// SLA/urgency of the ticket — Bassa | Media | Alta | Urgente. Never null: defaults to
  /// [kDefaultTicketPriority], mirroring the backend's own default so a technician who never
  /// touches the picker still sends an explicit, correct value.
  final String priority;

  NewTicketFormState copyWith({
    String? customerId,
    String? locationId,
    String? title,
    String? description,
    int? typeId,
    int? statusId,
    String? assignedUserId,
    String? priority,
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
      assignedUserId: clearAssignedUserId ? null : (assignedUserId ?? this.assignedUserId),
      priority: priority ?? this.priority,
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
