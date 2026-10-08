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
    this.dueDate,
    this.technicianNotes,
    this.agentId,
    this.contractId,
    this.commessaId,
    this.cantiereId,
    this.prodottoAssistenzaIds = const [],
    this.tags = const [],
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

  /// Scadenza — when the work is due. Optional, matches web's TicketCreatePanel.
  final DateTime? dueDate;

  /// Note tecnico — free text for the assigned technician. Distinct from `internalNotes` (office-
  /// only, deliberately not exposed on mobile) and from `description` (what the job is).
  final String? technicianNotes;

  /// Riferimento — the legacy "Agente" (`Core/Entities/Agent.cs`), a *different entity* from the
  /// technician in [assignedUserId]. The server validates this field with
  /// `EnsureExistsAsync<Agent>` (`TicketCommandService`), so it must carry an Agent id — a User id
  /// (what `/api/users?role=Technician` returns) 404s and, through the queue, silently drops the
  /// ticket. Sourced from the agents mirror, never from the technicians list.
  final String? agentId;

  /// Contratto — a customer's contract (`/api/contracts`, scoped by `customerId`). Optional
  /// enrichment; validated as `EnsureExistsAsync<Contract>`.
  final String? contractId;

  /// Commessa — a job order (`/api/commesse`, scoped by `customerId`). Optional; validated as
  /// `EnsureExistsAsync<Commessa>`.
  final String? commessaId;

  /// Cantiere — the worksite (`Core/Entities/Cantiere.cs`). Optional; validated as
  /// `EnsureExistsAsync<Cantiere>`.
  final String? cantiereId;

  /// Prodotti assistenza — the customer's assets this ticket covers. A list, defaults to empty
  /// and is never null: "no products" and "never opened the picker" are the same thing here, and a
  /// nullable list would only add a second empty to reason about. An empty list is sent as an
  /// absent member, never `[]` — see [TicketApiClient.createTicket].
  final List<String> prodottoAssistenzaIds;

  /// Free-form labels, no catalogue behind them — same reasoning as web's comma-separated input.
  final List<String> tags;

  NewTicketFormState copyWith({
    String? customerId,
    String? locationId,
    String? title,
    String? description,
    int? typeId,
    int? statusId,
    String? assignedUserId,
    String? priority,
    DateTime? dueDate,
    String? technicianNotes,
    String? agentId,
    String? contractId,
    String? commessaId,
    String? cantiereId,
    List<String>? prodottoAssistenzaIds,
    List<String>? tags,
    bool clearCustomerId = false,
    bool clearLocationId = false,
    bool clearTitle = false,
    bool clearDescription = false,
    bool clearTypeId = false,
    bool clearStatusId = false,
    bool clearAssignedUserId = false,
    bool clearDueDate = false,
    bool clearTechnicianNotes = false,
    bool clearAgentId = false,
    bool clearContractId = false,
    bool clearCommessaId = false,
    bool clearCantiereId = false,
    bool clearProdottoAssistenzaIds = false,
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
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      technicianNotes: clearTechnicianNotes ? null : (technicianNotes ?? this.technicianNotes),
      agentId: clearAgentId ? null : (agentId ?? this.agentId),
      contractId: clearContractId ? null : (contractId ?? this.contractId),
      commessaId: clearCommessaId ? null : (commessaId ?? this.commessaId),
      cantiereId: clearCantiereId ? null : (cantiereId ?? this.cantiereId),
      prodottoAssistenzaIds: clearProdottoAssistenzaIds
          ? const []
          : (prodottoAssistenzaIds ?? this.prodottoAssistenzaIds),
      tags: tags ?? this.tags,
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
