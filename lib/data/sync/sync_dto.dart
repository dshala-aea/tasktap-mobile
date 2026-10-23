// Dart DTOs for the MobileUserSyncResult payload.
// These mirror the C# entities serialised as JSON from GET /api/sync/mobile.
import '../../core/time/business_time.dart' show parseDateOnly, parseDateOnlyOrThrow;
import '../../core/time/work_time.dart' show parseTimeSpan;
import 'checklist_sync_dto.dart';

class SyncResultDto {
  final DateTime syncedAt;
  final DateTime? since;
  final List<ScheduleDto> schedules;
  final List<ReportDto> draftReports;

  /// Reports this technician submitted that have since left the draft state — Inviato,
  /// Controllato, Fatturato, Respinto, Annullato. Read-only on the device: this is what lets the
  /// Rapportini list (and the reject/rework affordance) show what happened to a report after it
  /// left the phone, instead of the device never learning the office rejected it. See
  /// `MobileUserSyncResult.SubmittedReports` (backend) for the query this mirrors.
  final List<ReportDto> submittedReports;
  final List<CustomerDto> customers;
  final List<LocationDto> locations;
  final List<TicketDto> tickets;
  final List<SyncTicketMaterialeDto> ticketMateriali;
  final List<MaterialeDto> materiali;
  final List<MaterialeBarcodeDto> materialiBarcodes;

  /// The tenant's active warehouses — every one of them, re-sent whole on every sync. The
  /// rapportino material line's source: without it, the furgone default and the "cambia magazzino"
  /// picker both needed a live call, and an offline line was saved with no provenance at all.
  final List<SyncMagazzinoDto> magazzini;
  final List<CantiereDto> cantieri;

  /// The crew of every cantiere [cantieri] carries this time — the complete set per cantiere, with
  /// no delta filter on these rows, so that a lead change reaches a device whose cantiere row
  /// itself did not change. Mirrored into `cantiere_crew_assignments` so the lead-only clock-in
  /// affordances and the teammate picker work offline (see SyncService).
  final List<SyncCantiereCrewAssignmentDto> cantiereCrewAssignments;

  final List<TicketStatusDto> ticketStatuses;
  final List<TicketTypeDto> ticketTypes;
  final List<ColleagueDto> colleagues;

  /// Every contact of every customer [customers] carries — the people a technician phones from the
  /// site. The complete list per customer, never delta-filtered: a contact has no tombstone, so the
  /// device replaces each customer's list from this payload instead of merging into it (see
  /// `SyncService`), and [carriesContacts] keeps an older backend from looking like a mass deletion.
  final List<CustomerContactDto> contacts;

  /// The reference entities a ticket is made of, mirrored so the create wizard can be filled from
  /// the local cache while offline (spec 6.2, 7.4). Scoped, never tenant-wide: contracts, commesse
  /// and products cover the customers this payload already carries, and agents cover the agents
  /// its tickets already reference.
  final List<ContractSyncDto> contracts;
  final List<CommessaSyncDto> commesse;
  final List<ProdottoAssistenzaSyncDto> prodottiAssistenza;
  final List<AgentSyncDto> agents;

  /// The maintenance checklist templates the technician may attach to a NEW ticket — the create
  /// wizard's "Modello checklist" picker. Scoped to the templates this technician's payload can see
  /// (curated plus this tenant's own); the whole visible set travels on every sync, so it is
  /// replaced wholesale rather than merged (see SyncService).
  final List<SyncMaintenanceTemplateDto> maintenanceTemplates;

  /// The tenant's active custom-field definitions, mirrored into `extension_field_definitions` so
  /// the "campi aggiuntivi" section renders with no network. The whole visible set travels every
  /// sync, so it is replaced wholesale (see `SyncService._replaceExtensionFieldDefinitions`).
  final List<SyncExtensionFieldDefinitionDto> extensionFieldDefinitions;

  final List<SyncControlGroupDto> controlGroups;
  final List<SyncTicketControlDto> ticketControls;
  final List<SyncTicketAssetDto> ticketAssets;
  final List<SyncAssetDto> assets;
  final List<SyncStrumentoDto> strumenti;
  final List<SyncReportStrumentoDto> reportStrumenti;

  /// The full aggregate of every report the payload covers: who worked on it, what was used,
  /// which checklist items were answered, which files it carries, and the row version of each.
  ///
  /// Headers alone left a report opened from sync a blank shell — the Rapportini list could show
  /// its state and dates, but its Squadra/Materiali/Controlli/Foto sections had nothing to render
  /// unless this device had authored or explicitly imported it. See
  /// `SyncService._applyReportAggregate` for the scope rules, which are the backend's: children
  /// travel in full for every report in scope on every sync, because a child deleted in the
  /// office has no change marker of its own.
  final List<SyncReportStaffDto> reportStaff;
  final List<SyncReportMaterialeDto> reportMateriali;
  final List<SyncReportControlloDto> reportControlli;

  /// Attachments for BOTH report and ticket entities, discriminated by `entityType`/`entityId`,
  /// active rows only. One list rather than two because that is what the payload sends and what
  /// `report_allegati` holds: that table has always carried ticket attachments too.
  final List<SyncReportAllegatoDto> allegati;

  /// `{reportId, version}` — the version `GET /api/reports/{id}` reports for that row, which is
  /// what the submit's stale-copy guard compares against (`DraftReports.expectedVersion`).
  final List<SyncReportVersionDto> reportVersions;

  /// The caller's OWN ticket timer sessions, replaced wholesale on every sync (see
  /// `SyncService._applyTicketTimers`). Only rows this user owns travel, so a supervisor's view of
  /// a colleague's hours stays an online read.
  final List<SyncTicketWorkLogDto> ticketWorkLogs;

  /// The recorded field changes of every ticket in scope — the Storico tab's timeline.
  ///
  /// Append-only on the server, so unlike every other member here the cutoff is exact: a full sync
  /// carries a window of it and each delta only what was written since. The applier therefore
  /// UPSERTS and never replaces a ticket's set; rows are pruned with their ticket, through the
  /// ticket manifest, because the payload has no manifest of its own for them.
  final List<SyncTicketHistoryDto> ticketHistory;

  /// The caller's OWN cantiere punches — the read mirror of site time. Re-sent in full on every
  /// sync (the window plus anything still open), so the applier upserts and the manifest prunes;
  /// a colleague's shift never travels here, the same rule as [ticketWorkLogs].
  ///
  /// Distinct from the local outbox (`cantiere_punches`), which holds punches this device still
  /// owes the server. Merging the two would put unsent state into a mirror of the server.
  final List<SyncCantiereWorkLogDto> cantiereWorkLogs;

  /// False when the payload came from a backend that predates the cantiere-punch mirror. Without
  /// it, an older server would look like "every shift was deleted" and the manifest prune would
  /// empty the device's site history — see `SyncService._pruneToScope`.
  final bool carriesCantiereWorkLogs;

  /// False when the payload came from a backend that predates the report aggregate. Without it an
  /// older backend would look like "every report lost its staff, materials and answers", and the
  /// per-report replace would delete children the device already holds.
  final bool carriesReportAggregate;

  /// Same, for the attachment list — kept apart because it is pruned over a different entity set
  /// (reports AND tickets) and travels under its own member.
  final bool carriesAllegati;

  /// True when the server stopped at its 5000-row cap. Informational: the authoritative list of
  /// what was left out is [checklistOmittedTicketIds].
  final bool checklistTruncated;

  /// Tickets whose checklist was NOT sent this time. The phone keeps whatever it already holds for
  /// them and asks again (see `refetchOmittedChecklists`).
  final List<String> checklistOmittedTicketIds;

  /// False when the payload came from a backend that predates the checklist members. Without this
  /// an older backend would look like "every checklist is empty" and a reconcile would wipe the
  /// cache.
  final bool carriesChecklist;
  final bool carriesStrumenti;

  /// False when the payload came from a backend that predates the reference members. Without these
  /// an older backend would look like "every contract, commessa and product was deleted" and the
  /// scoped prune would wipe the mirror. One flag per entity rather than one for the group: each is
  /// pruned independently, and a partial rollout must not be read as a deletion.
  final bool carriesContracts;
  final bool carriesCommesse;
  final bool carriesProdottiAssistenza;
  final bool carriesAgents;

  /// False when the payload came from a backend that predates the maintenance-template catalogue.
  /// Without it an older backend would look like "every template was deleted" and the wholesale
  /// replace would wipe the picker.
  final bool carriesMaintenanceTemplates;

  /// False when the payload came from a backend that predates the per-ticket fabbisogno mirror.
  /// Without it an older backend would look like "every ticket's planned materials were cleared"
  /// and the per-ticket replace would empty the Fabbisogno tab.
  final bool carriesTicketMateriali;
  /// False when the payload came from a backend that predates the cantiere-crew member. Without it
  /// an older backend would look like "every crew is empty" and the per-cantiere replace would wipe
  /// the mirror — the same trap [carriesMaintenanceTemplates] closes for the template catalogue.
  final bool carriesCantiereCrewAssignments;

  /// False when the payload came from a backend that predates the ticket-history member. Only
  /// informational: history is upsert-only and pruned by the ticket manifest, so a missing member
  /// deletes nothing — it just means this sync carries no timeline.
  final bool carriesTicketHistory;

  /// False when the payload came from a backend that predates the warehouse member. Without it an
  /// older backend would look like "the tenant has no warehouses" and the wholesale replace would
  /// empty the material picker's sources — the same trap [carriesMaintenanceTemplates] closes.
  final bool carriesMagazzini;

  /// False when the payload came from a backend that predates the extension-field definitions.
  /// Without it an older backend would look like "every custom field was deleted" and the
  /// wholesale replace would empty the section — the same trap
  /// [carriesMaintenanceTemplates] closes for the template catalogue.
  final bool carriesExtensionFieldDefinitions;

  /// False when the payload came from a backend that predates the customer-contacts member. Without
  /// it an older backend would look like "every customer lost their contacts" and the scoped replace
  /// would empty the Contatti section.
  final bool carriesContacts;

  /// The server's authoritative in-scope id sets, one nullable list per collection (sync v2).
  /// Null when the backend predates it — and null means NO PRUNE, never "everything left scope".
  /// See [SyncScopeDto] and [SyncService]'s prune.
  final SyncScopeDto? scope;

  static const Set<String> checklistWireKeys = {
    'controlGroups',
    'ticketControls',
    'ticketAssets',
    'assets',
    'strumenti',
    'reportStrumenti',
    'checklistTruncated',
    'checklistOmittedTicketIds',
  };

  /// The reference members, kept apart from [checklistWireKeys]: they carry the mirror the create
  /// wizard reads, not a ticket's checklist state. `ticketMateriali` rides here too — it is a
  /// mirrored, replace-on-arrival list like the rest, just scoped per ticket rather than per tenant.
  /// The reference members, kept apart from [checklistWireKeys]: they carry local mirrors, not a
  /// ticket's checklist state.
  ///
  /// `cantiereCrewAssignments` mirrors the crew of the payload's cantieri (who is assigned to each
  /// worksite and which of them is lead) into `cantiere_crew_assignments`, so the lead-only
  /// clock-in affordances and the teammate picker work offline. It is additive and old-backend
  /// tolerant: a server that predates the member omits the key, and
  /// [carriesCantiereCrewAssignments] then reads false so the mirror keeps whatever it holds
  /// instead of being wiped as "every crew is empty".
  static const Set<String> referenceWireKeys = {
    'contracts',
    'commesse',
    'prodottiAssistenza',
    'agents',
    'contacts',
    'maintenanceTemplates',
    'ticketMateriali',
    'cantiereCrewAssignments',
    'extensionFieldDefinitions',
    'magazzini',
  };

  /// The sync-v2 additions that travel beside the row lists: the authoritative scope and the
  /// barcode collection the offline scan resolves through.
  static const Set<String> scopeWireKeys = {'scope', 'materialiBarcodes'};

  /// The report aggregate (O-8a). Its own set rather than a member of [checklistWireKeys]: these
  /// rows describe reports, not a ticket's checklist, and the contract gate checks this group
  /// still names members `MobileUserSyncResult` declares.
  static const Set<String> reportAggregateWireKeys = {
    'reportStaff',
    'reportMateriali',
    'reportControlli',
    'allegati',
    'reportVersions',
  };

  /// The caller's own ticket timer sessions (O-9). Its own set for the same reason as the report
  /// aggregate: these rows fill the Ore tab and the running-timer indicator, not a ticket
  /// checklist, and the contract gate checks this group still names members
  /// `MobileUserSyncResult` declares.
  static const Set<String> ticketTimerWireKeys = {'ticketWorkLogs'};

  const SyncResultDto({
    required this.syncedAt,
    required this.since,
    required this.schedules,
    required this.draftReports,
    this.submittedReports = const [],
    required this.customers,
    required this.locations,
    required this.tickets,
    this.ticketMateriali = const [],
    required this.materiali,
    this.materialiBarcodes = const [],
    this.magazzini = const [],
    required this.cantieri,
    this.cantiereCrewAssignments = const [],
    required this.ticketStatuses,
    required this.ticketTypes,
    required this.colleagues,
    this.contacts = const [],
    this.contracts = const [],
    this.commesse = const [],
    this.prodottiAssistenza = const [],
    this.agents = const [],
    this.maintenanceTemplates = const [],
    this.extensionFieldDefinitions = const [],
    this.controlGroups = const [],
    this.ticketControls = const [],
    this.ticketAssets = const [],
    this.assets = const [],
    this.strumenti = const [],
    this.reportStrumenti = const [],
    this.reportStaff = const [],
    this.reportMateriali = const [],
    this.reportControlli = const [],
    this.allegati = const [],
    this.reportVersions = const [],
    this.ticketWorkLogs = const [],
    this.ticketHistory = const [],
    this.cantiereWorkLogs = const [],
    this.carriesCantiereWorkLogs = false,
    this.carriesReportAggregate = false,
    this.carriesAllegati = false,
    this.checklistTruncated = false,
    this.checklistOmittedTicketIds = const [],
    this.carriesChecklist = false,
    this.carriesStrumenti = false,
    this.carriesContracts = false,
    this.carriesCommesse = false,
    this.carriesProdottiAssistenza = false,
    this.carriesAgents = false,
    this.carriesMaintenanceTemplates = false,
    this.carriesTicketMateriali = false,
    this.carriesCantiereCrewAssignments = false,
    this.carriesTicketHistory = false,
    this.carriesMagazzini = false,
    this.carriesExtensionFieldDefinitions = false,
    this.carriesContacts = false,
    this.scope,
  });

  factory SyncResultDto.fromJson(Map<String, dynamic> j) {
    return SyncResultDto(
      syncedAt: DateTime.parse(j['syncedAt'] as String),
      since: j['since'] == null ? null : DateTime.parse(j['since'] as String),
      schedules: _list(j['schedules'], ScheduleDto.fromJson),
      draftReports: _list(j['draftReports'], ReportDto.fromJson),
      submittedReports: _list(j['submittedReports'], ReportDto.fromJson),
      customers: _list(j['customers'], CustomerDto.fromJson),
      locations: _list(j['locations'], LocationDto.fromJson),
      tickets: _list(j['tickets'], TicketDto.fromJson),
      ticketMateriali: _list(
        j['ticketMateriali'],
        SyncTicketMaterialeDto.fromJson,
      ),
      materiali: _list(j['materiali'], MaterialeDto.fromJson),
      materialiBarcodes: _list(
        j['materialiBarcodes'],
        MaterialeBarcodeDto.fromJson,
      ),
      magazzini: _list(j['magazzini'], SyncMagazzinoDto.fromJson),
      cantieri: _list(j['cantieri'], CantiereDto.fromJson),
      cantiereCrewAssignments: _list(
        j['cantiereCrewAssignments'],
        SyncCantiereCrewAssignmentDto.fromJson,
      ),
      ticketStatuses: _list(j['ticketStatuses'], TicketStatusDto.fromJson),
      ticketTypes: _list(j['ticketTypes'], TicketTypeDto.fromJson),
      colleagues: _list(j['colleagues'], ColleagueDto.fromJson),
      contacts: _list(j['contacts'], CustomerContactDto.fromJson),
      contracts: _list(j['contracts'], ContractSyncDto.fromJson),
      commesse: _list(j['commesse'], CommessaSyncDto.fromJson),
      prodottiAssistenza: _list(
        j['prodottiAssistenza'],
        ProdottoAssistenzaSyncDto.fromJson,
      ),
      agents: _list(j['agents'], AgentSyncDto.fromJson),
      maintenanceTemplates: _list(
        j['maintenanceTemplates'],
        SyncMaintenanceTemplateDto.fromJson,
      ),
      extensionFieldDefinitions: _list(
        j['extensionFieldDefinitions'],
        SyncExtensionFieldDefinitionDto.fromJson,
      ),
      controlGroups: _list(j['controlGroups'], SyncControlGroupDto.fromJson),
      ticketControls: _list(j['ticketControls'], SyncTicketControlDto.fromJson),
      ticketAssets: _list(j['ticketAssets'], SyncTicketAssetDto.fromJson),
      assets: _list(j['assets'], SyncAssetDto.fromJson),
      strumenti: _list(j['strumenti'], SyncStrumentoDto.fromJson),
      reportStrumenti: _list(
        j['reportStrumenti'],
        SyncReportStrumentoDto.fromJson,
      ),
      reportStaff: _list(j['reportStaff'], SyncReportStaffDto.fromJson),
      reportMateriali: _list(
        j['reportMateriali'],
        SyncReportMaterialeDto.fromJson,
      ),
      reportControlli: _list(
        j['reportControlli'],
        SyncReportControlloDto.fromJson,
      ),
      allegati: _list(j['allegati'], SyncReportAllegatoDto.fromJson),
      reportVersions: _list(
        j['reportVersions'],
        SyncReportVersionDto.fromJson,
      ),
      ticketWorkLogs: _list(
        j['ticketWorkLogs'],
        SyncTicketWorkLogDto.fromJson,
      ),
      ticketHistory: _list(
        j['ticketHistory'],
        SyncTicketHistoryDto.fromJson,
      ),
      cantiereWorkLogs: _list(
        j['cantiereWorkLogs'],
        SyncCantiereWorkLogDto.fromJson,
      ),
      checklistTruncated: j['checklistTruncated'] as bool? ?? false,
      checklistOmittedTicketIds:
          ((j['checklistOmittedTicketIds'] as List<dynamic>?) ?? const [])
              .cast<String>(),
      carriesChecklist: j.containsKey('ticketControls'),
      carriesStrumenti: j.containsKey('strumenti'),
      carriesContracts: j.containsKey('contracts'),
      carriesCommesse: j.containsKey('commesse'),
      carriesProdottiAssistenza: j.containsKey('prodottiAssistenza'),
      carriesAgents: j.containsKey('agents'),
      carriesMaintenanceTemplates: j.containsKey('maintenanceTemplates'),
      carriesReportAggregate: j.containsKey('reportStaff'),
      carriesAllegati: j.containsKey('allegati'),
      carriesTicketMateriali: j.containsKey('ticketMateriali'),
      carriesCantiereCrewAssignments: j.containsKey('cantiereCrewAssignments'),
      carriesTicketHistory: j.containsKey('ticketHistory'),
      carriesCantiereWorkLogs: j.containsKey('cantiereWorkLogs'),
      carriesMagazzini: j.containsKey('magazzini'),
      carriesExtensionFieldDefinitions: j.containsKey('extensionFieldDefinitions'),
      carriesContacts: j.containsKey('contacts'),
      scope: j['scope'] == null
          ? null
          : SyncScopeDto.fromJson(j['scope'] as Map<String, dynamic>),
    );
  }
}

// ── Scope ─────────────────────────────────────────────────────────────────────
//
// The authoritative in-scope id set per collection (sync v2). Distinct from the row lists it
// travels with: on a delta those carry only what changed after the cursor, while this carries
// everything still in scope. The phone prunes what is absent — see `SyncService`'s prune.
//
// Nullability is load-bearing in BOTH directions:
//   * the whole object null   → an older backend, or a server that could not compute scope:
//                                no authoritative set at all, so no prune;
//   * a member null           → this caller is not delivered that collection at all (today:
//                                `strumenti` without `team.strumento.read`): no prune for it;
//   * a member `[]`           → genuinely nothing is in scope: everything local goes.
// That is why every member is `List<String>?` and not a non-null list with an `isEmpty` flag.
class SyncScopeDto {
  const SyncScopeDto({
    this.schedules,
    this.tickets,
    this.locations,
    this.customers,
    this.cantieri,
    this.agents,
    this.draftReports,
    this.submittedReports,
    this.materiali,
    this.materialiBarcodes,
    this.strumenti,
    this.ticketWorkLogs,
    this.cantiereWorkLogs,
  });

  final List<String>? schedules;
  final List<String>? tickets;
  final List<String>? locations;
  final List<String>? customers;
  final List<String>? cantieri;
  final List<String>? agents;
  final List<String>? draftReports;
  final List<String>? submittedReports;
  final List<String>? materiali;
  final List<String>? materialiBarcodes;
  final List<String>? strumenti;

  /// The caller's own ticket timer sessions the server currently holds in scope (the 90-day window
  /// plus any still running). Null on an older backend → no prune. Never includes another user's
  /// session, so this never says a colleague's rows were deleted.
  final List<String>? ticketWorkLogs;

  /// The caller's own cantiere punches the server currently holds in scope (the window plus any
  /// still-open shift). Null on an older backend → no prune, so a server that predates the member
  /// cannot empty the device's site history. Never includes a colleague's punch.
  final List<String>? cantiereWorkLogs;

  /// The exact keys `fromJson` reads — compared with the OpenAPI snapshot by the inbound
  /// contract gate.
  static const Set<String> wireKeys = {
    'schedules',
    'tickets',
    'locations',
    'customers',
    'cantieri',
    'agents',
    'draftReports',
    'submittedReports',
    'materiali',
    'materialiBarcodes',
    'strumenti',
    'ticketWorkLogs',
    'cantiereWorkLogs',
  };

  factory SyncScopeDto.fromJson(Map<String, dynamic> j) => SyncScopeDto(
    schedules: _idList(j['schedules']),
    tickets: _idList(j['tickets']),
    locations: _idList(j['locations']),
    customers: _idList(j['customers']),
    cantieri: _idList(j['cantieri']),
    agents: _idList(j['agents']),
    draftReports: _idList(j['draftReports']),
    submittedReports: _idList(j['submittedReports']),
    materiali: _idList(j['materiali']),
    materialiBarcodes: _idList(j['materialiBarcodes']),
    strumenti: _idList(j['strumenti']),
    ticketWorkLogs: _idList(j['ticketWorkLogs']),
    cantiereWorkLogs: _idList(j['cantiereWorkLogs']),
  );

  /// Null stays null ("no authoritative set"); an empty array stays an empty list ("nothing in
  /// scope"). Never collapse the two.
  static List<String>? _idList(dynamic v) =>
      v == null ? null : (v as List<dynamic>).cast<String>();
}

// ── Colleague ──────────────────────────────────────────────────────────────────

/// A colleague the technician can name on a rapportino. Id and display name only — see the
/// server's SyncColleagueDto for why the rest of the user row does not travel to a phone.
class ColleagueDto {
  final String id;
  final String displayName;

  const ColleagueDto({required this.id, required this.displayName});

  factory ColleagueDto.fromJson(Map<String, dynamic> j) => ColleagueDto(
    id: j['id'] as String,
    displayName: j['displayName'] as String? ?? '',
  );
}

// ── Customer contacts ─────────────────────────────────────────────────────────

/// One person at a customer site, as the office recorded them.
///
/// Mirrored so the customer screen's *Contatti* section renders from the local cache: it used to
/// call `GET /api/customers/{id}/contacts` on every open and show an error card offline, which is
/// exactly where a technician needs a phone number. See the backend's
/// `MobileUserSyncResult.Contacts` for the scoping and why it is never delta-filtered.
class CustomerContactDto {
  final String id;

  /// The audit members every synced entity carries. None of them is rendered on the phone: the
  /// contact card shows a name, a role and the two ways of reaching that person. They are read
  /// anyway because the inbound contract gate compares this class's key set with the server's
  /// schema in BOTH directions — a schema member the app silently ignores is exactly the drift the
  /// gate exists to make visible, and `MaterialeBarcodeDto` set this precedent.
  final String? tenantId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Who last edited the contact, on the office side. Carried, never shown; see [tenantId].
  final String? updatedByUserId;

  final String customerId;
  final String name;
  final String? role;
  final String? phone;
  final String? email;
  final String? notes;

  const CustomerContactDto({
    required this.id,
    required this.customerId,
    required this.name,
    this.tenantId,
    this.createdAt,
    this.updatedAt,
    this.updatedByUserId,
    this.role,
    this.phone,
    this.email,
    this.notes,
  });

  factory CustomerContactDto.fromJson(Map<String, dynamic> j) => CustomerContactDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String?,
    createdAt: _dt(j['createdAt']),
    updatedAt: _dt(j['updatedAt']),
    updatedByUserId: j['updatedByUserId'] as String?,
    customerId: j['customerId'] as String,
    name: j['name'] as String? ?? '',
    role: j['role'] as String?,
    phone: j['phone'] as String?,
    email: j['email'] as String?,
    notes: j['notes'] as String?,
  );

  /// The exact keys [fromJson] reads, for the inbound contract gate — see
  /// `test/contract/sync_inbound_contract_test.dart`.
  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'createdAt',
    'updatedAt',
    'updatedByUserId',
    'customerId',
    'name',
    'role',
    'phone',
    'email',
    'notes',
  };
}

// ── Customer ───────────────────────────────────────────────────────────────────

class CustomerDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String companyName;
  final String? taxId;
  final String? address;
  final String? city;
  final String? postalCode;
  final String? country;
  final String? phone;
  final String? email;
  final String? contactPerson;
  final String? notes;
  final bool isActive;

  /// `Customer.AgentId` — the customer's one agent, which pre-fills a new ticket's Riferimento.
  /// Absent from an older backend's payload, which reads as null: no pre-fill, never an error.
  final String? agentId;

  /// Mobile number, distinct from the landline [phone] (`cellulare` on the wire).
  final String? cellulare;

  /// Codice Fiscale — `fiscalCode` on the wire, not `codiceFiscale`: the server entity overrides
  /// its own name and the default camelCase policy would emit the wrong key. Null on an older
  /// backend's payload, which is simply "unknown", never an error.
  final String? fiscalCode;

  /// Codice Destinatario SDI — `sdiCode` on the wire.
  final String? sdiCode;

  /// PEC address — `pec` on the wire (`PECEmail` on the entity).
  final String? pec;

  /// Province code (sigla) — `province` on the wire (`Provincia` on the entity).
  final String? province;

  const CustomerDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.companyName,
    this.taxId,
    this.address,
    this.city,
    this.postalCode,
    this.country,
    this.phone,
    this.email,
    this.contactPerson,
    this.notes,
    this.isActive = true,
    this.agentId,
    this.cellulare,
    this.fiscalCode,
    this.sdiCode,
    this.pec,
    this.province,
  });

  factory CustomerDto.fromJson(Map<String, dynamic> j) => CustomerDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    companyName: j['companyName'] as String,
    taxId: j['taxId'] as String?,
    address: j['address'] as String?,
    city: j['city'] as String?,
    postalCode: j['postalCode'] as String?,
    country: j['country'] as String?,
    phone: j['phone'] as String?,
    email: j['email'] as String?,
    contactPerson: j['contactPerson'] as String?,
    notes: j['notes'] as String?,
    isActive: j['isActive'] as bool? ?? true,
    agentId: j['agentId'] as String?,
    cellulare: j['cellulare'] as String?,
    fiscalCode: j['fiscalCode'] as String?,
    sdiCode: j['sdiCode'] as String?,
    pec: j['pec'] as String?,
    province: j['province'] as String?,
  );
}

// ── Location ───────────────────────────────────────────────────────────────────

class LocationDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String customerId;
  final String name;
  final String? address;
  final String? city;
  final String? postalCode;
  final String? country;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? notes;
  final bool isActive;

  const LocationDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.customerId,
    required this.name,
    this.address,
    this.city,
    this.postalCode,
    this.country,
    this.latitude,
    this.longitude,
    this.phone,
    this.notes,
    this.isActive = true,
  });

  factory LocationDto.fromJson(Map<String, dynamic> j) => LocationDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    customerId: j['customerId'] as String,
    name: j['name'] as String,
    address: j['address'] as String?,
    city: j['city'] as String?,
    postalCode: j['postalCode'] as String?,
    country: j['country'] as String?,
    latitude: _dbl(j['latitude']),
    longitude: _dbl(j['longitude']),
    phone: j['phone'] as String?,
    notes: j['notes'] as String?,
    isActive: j['isActive'] as bool? ?? true,
  );
}

// ── Ticket ─────────────────────────────────────────────────────────────────────

class TicketDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String title;

  /// The per-tenant display number — what a technician and the customer both call this job.
  ///
  /// It has been on the wire the whole time: mobile sync returns the `Ticket` entity itself and
  /// the entity carries `Numero`. This client simply never read it, so every ticket surface fell
  /// back to `id.substring(0, 8)` and titled the screen with eight hex characters of a GUID.
  ///
  /// Null for tickets created before numbering existed. Null means *no number*, and the UI shows
  /// nothing rather than reaching for the id again.
  final String? numero;

  final String? description;
  final String customerId;
  final String locationId;
  final String? assignedUserId;
  final int statusId;
  final int typeId;
  final String? agentId;
  final DateTime? closedAt;
  final String? technicianNotes;
  final String? internalNotes;
  final String? contractId;
  final String? prodottoAssistenzaId;
  final String? commessaId;

  /// The cantiere this ticket is linked to, when it has one. See `Tickets.cantiereId`'s own doc
  /// comment in app_database.dart for why this needed a schema+cursor bump to actually reach the
  /// device rather than just being added to this DTO.
  final String? cantiereId;

  /// Wire form is the enum name — see `Tickets.priority`'s own doc comment in `app_database.dart`.
  final String? priority;

  /// A CIVIL date (`DateTime.utc(y, m, d)`), not the instant the wire spells it as — see
  /// `Tickets.dueDate`'s own doc comment in `app_database.dart`. `parseDateOnly` keeps whatever day
  /// the server named rather than letting a zone conversion move it.
  final DateTime? dueDate;

  /// Free-form labels — see `Tickets.tagsJson`'s own doc comment in `app_database.dart`.
  final List<String> tags;

  /// The tenant's custom-field values for this ticket, as the server's raw JSON-object text.
  ///
  /// On the wire this is a JSON *string* holding JSON — `Ticket.ExtensionValues` is a `string?` over
  /// a Postgres `jsonb` column, so System.Text.Json writes it quoted — hence `String?` here and a
  /// double decode at the point of use. Null means the ticket has no custom-field values.
  final String? extensionValues;

  const TicketDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.title,
    this.numero,
    this.description,
    required this.customerId,
    required this.locationId,
    this.assignedUserId,
    required this.statusId,
    required this.typeId,
    this.agentId,
    this.closedAt,
    this.technicianNotes,
    this.internalNotes,
    this.contractId,
    this.prodottoAssistenzaId,
    this.commessaId,
    this.cantiereId,
    this.priority,
    this.dueDate,
    this.tags = const [],
    this.extensionValues,
  });

  factory TicketDto.fromJson(Map<String, dynamic> j) => TicketDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    title: j['title'] as String,
    numero: j['numero'] as String?,
    description: j['description'] as String?,
    customerId: j['customerId'] as String,
    locationId: j['locationId'] as String,
    assignedUserId: j['assignedUserId'] as String?,
    statusId: (j['statusId'] as num).toInt(),
    typeId: (j['typeId'] as num).toInt(),
    agentId: j['agentId'] as String?,
    closedAt: _dt(j['closedAt']),
    technicianNotes: j['technicianNotes'] as String?,
    internalNotes: j['internalNotes'] as String?,
    contractId: j['contractId'] as String?,
    prodottoAssistenzaId: j['prodottoAssistenzaId'] as String?,
    commessaId: j['commessaId'] as String?,
    cantiereId: j['cantiereId'] as String?,
    priority: j['priority'] as String?,
    dueDate: parseDateOnly(j['dueDate']),
    tags: (j['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
    extensionValues: j['extensionValues'] as String?,
  );
}

// ── Materiale ──────────────────────────────────────────────────────────────────

class MaterialeDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String code;
  final String name;
  final String? description;
  final String? unitOfMeasure;
  final String? category;
  final String? marca;
  final double? purchasePrice;
  final double? salePrice;
  final bool isActive;

  const MaterialeDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.code,
    required this.name,
    this.description,
    this.unitOfMeasure,
    this.category,
    this.marca,
    this.purchasePrice,
    this.salePrice,
    this.isActive = true,
  });

  factory MaterialeDto.fromJson(Map<String, dynamic> j) => MaterialeDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    code: j['code'] as String,
    name: j['name'] as String,
    description: j['description'] as String?,
    unitOfMeasure: j['unitOfMeasure'] as String?,
    category: j['category'] as String?,
    marca: j['marca'] as String?,
    // decimal? fields serialise as either a JSON number or a string
    // (pattern-validated), same idiom as ReportMateriale.UnitPrice — see
    // Materiale.AliquotaIVA's XML doc for why.
    purchasePrice: _dbl(j['purchasePrice']),
    salePrice: _dbl(j['salePrice']),
    isActive: j['isActive'] as bool? ?? true,
  );
}

// ── TicketMateriale (fabbisogno) ─────────────────────────────────────────────
//
// Mirrors the backend's raw TicketMateriale entity field-for-field — not the Italian-translated
// shape the per-ticket detail REST endpoint's own response DTO uses (see TicketMaterialeDto in
// ticket_detail_api_client.dart, which stays the online source of truth for that screen). This
// one is only ever read into the local Drift mirror.
class SyncTicketMaterialeDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String ticketId;
  final String? materialeId;
  final String? freeTextName;
  final double quantity;
  final String? unitOfMeasure;
  final String? notes;
  final bool isAvailable;

  const SyncTicketMaterialeDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.ticketId,
    this.materialeId,
    this.freeTextName,
    required this.quantity,
    this.unitOfMeasure,
    this.notes,
    this.isAvailable = false,
  });

  factory SyncTicketMaterialeDto.fromJson(Map<String, dynamic> j) =>
      SyncTicketMaterialeDto(
        id: j['id'] as String,
        tenantId: j['tenantId'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: _dt(j['updatedAt']),
        ticketId: j['ticketId'] as String,
        materialeId: j['materialeId'] as String?,
        freeTextName: j['freeTextName'] as String?,
        quantity: _dbl(j['quantity']) ?? 0,
        unitOfMeasure: j['unitOfMeasure'] as String?,
        notes: j['notes'] as String?,
        isAvailable: j['isAvailable'] as bool? ?? false,
      );
}

// ── MaterialeBarcode ─────────────────────────────────────────────────────────
//
// Mirrors the backend's SyncMaterialeBarcodeDto — a barcode/QR code tied to a Materiale, for
// offline scan-to-lookup. See MaterialeBarcodes (local Drift table) for why this is delta-synced
// independently of its parent MaterialeDto.
class MaterialeBarcodeDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String materialeId;
  final String barcode;
  final String? barcodeType;
  final bool isPrimary;

  const MaterialeBarcodeDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.materialeId,
    required this.barcode,
    this.barcodeType,
    this.isPrimary = false,
  });

  /// The exact keys `fromJson` reads — compared with the OpenAPI snapshot by the inbound
  /// contract gate. The server carries all eight on the wire (including the nullable ones, which
  /// it must send rather than omit: this parser reads them unconditionally).
  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'createdAt',
    'updatedAt',
    'materialeId',
    'barcode',
    'barcodeType',
    'isPrimary',
  };

  factory MaterialeBarcodeDto.fromJson(Map<String, dynamic> j) =>
      MaterialeBarcodeDto(
        id: j['id'] as String,
        tenantId: j['tenantId'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: _dt(j['updatedAt']),
        materialeId: j['materialeId'] as String,
        barcode: j['barcode'] as String,
        barcodeType: j['barcodeType'] as String?,
        isPrimary: j['isPrimary'] as bool? ?? false,
      );
}

// ── Magazzino ────────────────────────────────────────────────────────────────
//
// Mirrors the backend's SyncMagazzinoDto: the tenant's warehouse rows, so the rapportino material
// picker can name a line's source with no signal. See Magazzini (local Drift table) for the bug
// this closes.
class SyncMagazzinoDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String nome;

  /// `"Sede"` or `"Furgone"` — the enum's own `JsonStringEnumConverter` label, the same string
  /// [MagazzinoDto.tipo] carries from the REST endpoints.
  final String tipo;

  /// For a Furgone: the technician it is assigned to. Null for a Sede.
  final String? assegnatoUserId;
  final bool isActive;

  const SyncMagazzinoDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.nome,
    required this.tipo,
    this.assegnatoUserId,
    this.isActive = true,
  });

  /// The exact keys `fromJson` reads — compared with the OpenAPI snapshot by the inbound
  /// contract gate. The server carries all eight unconditionally, nullable ones included.
  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'createdAt',
    'updatedAt',
    'nome',
    'tipo',
    'assegnatoUserId',
    'isActive',
  };

  factory SyncMagazzinoDto.fromJson(Map<String, dynamic> j) => SyncMagazzinoDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    nome: j['nome'] as String,
    tipo: j['tipo'] as String? ?? 'Sede',
    assegnatoUserId: j['assegnatoUserId'] as String?,
    isActive: j['isActive'] as bool? ?? true,
  );
}

// ── Cantiere ───────────────────────────────────────────────────────────────────

/// CantiereStatusEnum values, in the same order as the backend enum
/// (`[JsonConverter(typeof(JsonStringEnumConverter))] enum CantiereStatusEnum`)
/// and as the `Cantieri.status` Drift column (Active=0, Completed=1, Cancelled=2).
const _cantiereStatusValues = <String, int>{
  'Active': 0,
  'Completed': 1,
  'Cancelled': 2,
};

/// Parses the wire enum string to the int the Drift column stores.
/// Unknown/missing values default to Active — the safest fallback for a
/// picker that filters on "active" cantieri (see [CantieriProvider] usage).
int parseCantiereStatus(dynamic v) => _cantiereStatusValues[v as String?] ?? 0;

class CantiereDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String name;
  final String? address;
  final String? city;
  final String? postalCode;
  final String? notes;
  final DateTime? startDate;
  final DateTime? endDate;
  final int status;
  final String? customerId;
  final String? commessaId;

  /// The tenant's custom-field values for this cantiere, raw JSON-object text — see
  /// `TicketDto.extensionValues` for the double-encoded wire shape.
  final String? extensionValues;

  const CantiereDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.name,
    this.address,
    this.city,
    this.postalCode,
    this.notes,
    this.startDate,
    this.endDate,
    this.status = 0,
    this.customerId,
    this.commessaId,
    this.extensionValues,
  });

  factory CantiereDto.fromJson(Map<String, dynamic> j) => CantiereDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    name: j['name'] as String,
    address: j['address'] as String?,
    city: j['city'] as String?,
    postalCode: j['postalCode'] as String?,
    notes: j['notes'] as String?,
    startDate: _dt(j['startDate']),
    endDate: _dt(j['endDate']),
    status: parseCantiereStatus(j['status']),
    customerId: j['customerId'] as String?,
    commessaId: j['commessaId'] as String?,
    extensionValues: j['extensionValues'] as String?,
  );
}

// ── Tenant extension-field definitions ─────────────────────────────────────────

/// One `extensionFieldDefinitions[]` row — a tenant-configured custom field ("campo aggiuntivo")
/// for an extensible entity type.
///
/// Mirrors the server's `SyncExtensionFieldDefinitionDto`, which itself carries exactly the members
/// `ExtensionFieldDefinitionSummaryDto` hands the office forms — so the mirrored section renders
/// the same online and offline. `showInList` travels on the wire (it is an office-grid concern) and
/// is deliberately not read here: nothing on the phone renders a list column from it.
class SyncExtensionFieldDefinitionDto {
  final String id;
  final String key;
  final String label;
  final String entityType;
  final String fieldType;
  final bool isRequired;
  final bool showInCard;
  final int sortOrder;
  final String? options;
  final String? unit;
  final String? defaultValue;
  final String? placeholder;

  const SyncExtensionFieldDefinitionDto({
    required this.id,
    required this.key,
    required this.label,
    required this.entityType,
    required this.fieldType,
    this.isRequired = false,
    this.showInCard = false,
    this.sortOrder = 0,
    this.options,
    this.unit,
    this.defaultValue,
    this.placeholder,
  });

  /// Exactly the keys [fromJson] reads — the inbound contract test compares this with the
  /// server's declared schema in both directions, so a member added on one side alone fails.
  static const Set<String> wireKeys = {
    'id',
    'key',
    'label',
    'entityType',
    'fieldType',
    'isRequired',
    'showInList',
    'showInCard',
    'sortOrder',
    'options',
    'unit',
    'defaultValue',
    'placeholder',
  };

  factory SyncExtensionFieldDefinitionDto.fromJson(Map<String, dynamic> j) =>
      SyncExtensionFieldDefinitionDto(
        id: j['id'] as String,
        key: j['key'] as String,
        label: j['label'] as String,
        entityType: j['entityType'] as String,
        fieldType: j['fieldType'] as String? ?? 'text',
        isRequired: j['isRequired'] as bool? ?? false,
        showInCard: j['showInCard'] as bool? ?? false,
        sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
        options: j['options'] as String?,
        unit: j['unit'] as String?,
        defaultValue: j['defaultValue'] as String?,
        placeholder: j['placeholder'] as String?,
      );
}

// ── Cantiere crew assignment ────────────────────────────────────────────────────

/// One `cantiereCrewAssignments[]` row — a person assigned to a cantiere, and whether they are its
/// lead.
///
/// Mirrors the server's `CantiereCrewAssignment` through the sync payload rather than the
/// paginated `GET /api/cantieri/{id}/assegnazioni` shape the live client parses: the same facts,
/// plus the `cantiereId` the live endpoint already has in its path. Ids are Guids on the wire and
/// stay strings here, exactly like every other sync DTO.
class SyncCantiereCrewAssignmentDto {
  final String id;
  final String cantiereId;
  final String userId;
  final bool isLead;

  const SyncCantiereCrewAssignmentDto({
    required this.id,
    required this.cantiereId,
    required this.userId,
    this.isLead = false,
  });

  /// Exactly the keys [fromJson] reads — the inbound contract test compares this with the
  /// server's declared schema in both directions, so a member added on one side alone fails.
  static const Set<String> wireKeys = {'id', 'cantiereId', 'userId', 'isLead'};

  factory SyncCantiereCrewAssignmentDto.fromJson(Map<String, dynamic> j) =>
      SyncCantiereCrewAssignmentDto(
        id: j['id'] as String,
        cantiereId: j['cantiereId'] as String,
        userId: j['userId'] as String,
        isLead: j['isLead'] as bool? ?? false,
      );
}

// ── TicketStatus ───────────────────────────────────────────────────────────────

class TicketStatusDto {
  final int id;
  final String tenantId;
  final String name;
  final bool isDefault;
  final bool isClosed;

  const TicketStatusDto({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.isDefault,
    required this.isClosed,
  });

  factory TicketStatusDto.fromJson(Map<String, dynamic> j) => TicketStatusDto(
    id: (j['id'] as num).toInt(),
    tenantId: j['tenantId'] as String,
    name: j['name'] as String,
    isDefault: j['isDefault'] as bool? ?? false,
    isClosed: j['isClosed'] as bool? ?? false,
  );
}

// ── TicketType ─────────────────────────────────────────────────────────────────

class TicketTypeDto {
  final int id;
  final String tenantId;
  final String name;
  final String? description;

  const TicketTypeDto({
    required this.id,
    required this.tenantId,
    required this.name,
    this.description,
  });

  factory TicketTypeDto.fromJson(Map<String, dynamic> j) => TicketTypeDto(
    id: (j['id'] as num).toInt(),
    tenantId: j['tenantId'] as String,
    name: j['name'] as String,
    description: j['description'] as String?,
  );
}

// ── Schedule ───────────────────────────────────────────────────────────────────

class ScheduleDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? ticketId;
  final DateTime activityDate;

  /// TimeStart serialised as "hh:mm:ss" string (C# TimeSpan JSON default)
  final String timeStart;

  /// TimeEnd serialised as "hh:mm:ss" string
  final String timeEnd;
  final String userId;
  final int statusId;
  final String locationId;
  final bool allDay;
  final String title;
  final String description;

  /// Everyone on this schedule, with every reason they are on it.
  ///
  /// Replaces teamLeadId / staffIds / squadraId, which the server dropped (backend ADR-0009).
  /// Those three expressed three overlapping halves of one answer and could not express the
  /// fourth at all: a job assigned to a squadra named nobody the device could see.
  final List<ScheduleAssigneeDto> assignees;

  const ScheduleDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    this.ticketId,
    required this.activityDate,
    required this.timeStart,
    required this.timeEnd,
    required this.userId,
    required this.statusId,
    required this.locationId,
    required this.allDay,
    required this.title,
    required this.description,
    this.assignees = const [],
  });

  factory ScheduleDto.fromJson(Map<String, dynamic> j) {
    // TimeSpan comes as "HH:MM:SS" from System.Text.Json default serialization
    final tsRaw = j['timeStart'] as String? ?? '00:00:00';
    final teRaw = j['timeEnd'] as String? ?? '00:00:00';

    return ScheduleDto(
      id: j['id'] as String,
      tenantId: j['tenantId'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: _dt(j['updatedAt']),
      ticketId: j['ticketId'] as String?,
      activityDate: DateTime.parse(j['activityDate'] as String),
      timeStart: tsRaw,
      timeEnd: teRaw,
      userId: j['userId'] as String,
      statusId: (j['statusId'] as num).toInt(),
      locationId: j['locationId'] as String,
      allDay: j['allDay'] as bool? ?? false,
      title: j['title'] as String? ?? '',
      description: j['description'] as String? ?? '',
      assignees: (j['assignees'] as List<dynamic>? ?? const [])
          .map((e) => ScheduleAssigneeDto.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  /// The directly assigned technician, or null when the job is only assigned to a squadra.
  ///
  /// [userId] still carries the same value the server sends, and the server still sends the
  /// all-zeros guid when there is nobody — this is the honest reading of it.
  String? get directAssigneeId {
    for (final a in assignees) {
      if (a.isDirect) return a.userId;
    }
    return null;
  }

  /// Parse "HH:MM:SS" → total minutes since midnight.
  static int parseTimeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }
}

// ── ScheduleAssignee ───────────────────────────────────────────────────────────

/// One person on a schedule, carrying every reason they are on it rather than only the
/// strongest.
///
/// The flags are deliberately not collapsed into a single "role". A screen asking "may this
/// person write the rapportino" reads [isLead]; one asking "who is on the squadra" reads
/// [isTeam]. A single winner would make the second question unanswerable without another call —
/// which is how the server-side model went wrong in the first place.
class ScheduleAssigneeDto {
  final String userId;
  final bool isUserActive;
  final bool isDirect;
  final bool isLead;
  final bool isTeam;
  final bool isLegacyStaff;

  const ScheduleAssigneeDto({
    required this.userId,
    this.isUserActive = true,
    this.isDirect = false,
    this.isLead = false,
    this.isTeam = false,
    this.isLegacyStaff = false,
  });

  factory ScheduleAssigneeDto.fromJson(Map<String, dynamic> j) =>
      ScheduleAssigneeDto(
        userId: j['userId'] as String,
        isUserActive: j['isUserActive'] as bool? ?? true,
        isDirect: j['isDirect'] as bool? ?? false,
        isLead: j['isLead'] as bool? ?? false,
        isTeam: j['isTeam'] as bool? ?? false,
        isLegacyStaff: j['isLegacyStaff'] as bool? ?? false,
      );
}

// ── Report (draft) ─────────────────────────────────────────────────────────────

class ReportDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String title;
  final String? scheduleId;
  final String? ticketId;
  final String? customerId;
  final String? cantiereId;
  final String? details;
  final String? diagnosi;
  final String? soluzione;
  final String insertedUserId;
  final String locationId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? documentTemplateId;
  final String? customerSignatureAllegatoId;
  final String? technicianSignatureAllegatoId;
  final String? technicianNotes;
  final DateTime? closedAt;
  final String stato;
  final DateTime? inviatoAt;
  final DateTime? controllatoAt;
  final String? controllatoDa;
  final DateTime? fatturatoAt;
  final bool materialiNotRequired;
  final String? customerSignoffText;
  final DateTime? customerSignoffAt;

  /// The tenant's custom-field values for this rapportino, raw JSON-object text — see
  /// `TicketDto.extensionValues` for the double-encoded wire shape.
  final String? extensionValues;

  const ReportDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.title,
    this.scheduleId,
    this.ticketId,
    this.customerId,
    this.cantiereId,
    this.details,
    this.diagnosi,
    this.soluzione,
    required this.insertedUserId,
    required this.locationId,
    this.startedAt,
    this.endedAt,
    this.documentTemplateId,
    this.customerSignatureAllegatoId,
    this.technicianSignatureAllegatoId,
    this.technicianNotes,
    this.closedAt,
    this.stato = 'Bozza',
    this.inviatoAt,
    this.controllatoAt,
    this.controllatoDa,
    this.fatturatoAt,
    this.materialiNotRequired = false,
    this.customerSignoffText,
    this.customerSignoffAt,
    this.extensionValues,
  });

  factory ReportDto.fromJson(Map<String, dynamic> j) => ReportDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    title: j['title'] as String,
    scheduleId: j['scheduleId'] as String?,
    ticketId: j['ticketId'] as String?,
    customerId: j['customerId'] as String?,
    cantiereId: j['cantiereId'] as String?,
    details: j['details'] as String?,
    diagnosi: j['diagnosi'] as String?,
    soluzione: j['soluzione'] as String?,
    insertedUserId: j['insertedUserId'] as String,
    locationId: j['locationId'] as String,
    startedAt: _dt(j['startedAt']),
    endedAt: _dt(j['endedAt']),
    documentTemplateId: j['documentTemplateId'] as String?,
    customerSignatureAllegatoId: j['customerSignatureAllegatoId'] as String?,
    technicianSignatureAllegatoId:
        j['technicianSignatureAllegatoId'] as String?,
    technicianNotes: j['technicianNotes'] as String?,
    closedAt: _dt(j['closedAt']),
    stato: j['stato'] as String? ?? 'Bozza',
    inviatoAt: _dt(j['inviatoAt']),
    controllatoAt: _dt(j['controllatoAt']),
    controllatoDa: j['controllatoDa'] as String?,
    fatturatoAt: _dt(j['fatturatoAt']),
    materialiNotRequired: j['materialiNotRequired'] as bool? ?? false,
    customerSignoffText: j['customerSignoffText'] as String?,
    customerSignoffAt: _dt(j['customerSignoffAt']),
    extensionValues: j['extensionValues'] as String?,
  );
}

// ── Reference entities ──────────────────────────────────────────────────────────
//
// The four mirrors the create wizard fills from while offline (spec 6.2, 7.4). Each one publishes
// `wireKeys` — the exact keys its `fromJson` reads — because the inbound contract test compares
// them with the OpenAPI snapshot in both directions.

/// A contract of a customer in this technician's payload. Mirrored for the Cliente→Contratto picker
/// (spec 7.4). [isActive] is stored, never filtered here — the picker is what hides a deactivated
/// contract.
class ContractSyncDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String name;
  final String customerId;
  final String? locationId;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isActive;
  final String? numero;
  final String? codice;
  final int? tipo;
  final String? externalId;

  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'createdAt',
    'updatedAt',
    'name',
    'customerId',
    'locationId',
    'startDate',
    'endDate',
    'isActive',
    'numero',
    'codice',
    'tipo',
    'externalId',
  };

  const ContractSyncDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.name,
    required this.customerId,
    this.locationId,
    required this.startDate,
    this.endDate,
    this.isActive = true,
    this.numero,
    this.codice,
    this.tipo,
    this.externalId,
  });

  factory ContractSyncDto.fromJson(Map<String, dynamic> j) => ContractSyncDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    name: j['name'] as String,
    customerId: j['customerId'] as String,
    locationId: j['locationId'] as String?,
    startDate: DateTime.parse(j['startDate'] as String),
    endDate: _dt(j['endDate']),
    isActive: j['isActive'] as bool? ?? true,
    numero: j['numero'] as String?,
    codice: j['codice'] as String?,
    tipo: _intOrNull(j['tipo']),
    externalId: j['externalId'] as String?,
  );
}

/// A commessa (job order) of a customer in this payload. [customerId] is nullable on the wire —
/// the server's `SyncCommessaDto` declares `Guid? CustomerId`.
class CommessaSyncDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String codice;
  final String? descrizione;
  final String? customerId;
  final bool isActive;
  final String? stato;
  final String? externalId;

  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'createdAt',
    'updatedAt',
    'codice',
    'descrizione',
    'customerId',
    'isActive',
    'stato',
    'externalId',
  };

  const CommessaSyncDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.codice,
    this.descrizione,
    this.customerId,
    this.isActive = true,
    this.stato,
    this.externalId,
  });

  factory CommessaSyncDto.fromJson(Map<String, dynamic> j) => CommessaSyncDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    codice: j['codice'] as String,
    descrizione: j['descrizione'] as String?,
    customerId: j['customerId'] as String?,
    isActive: j['isActive'] as bool? ?? true,
    stato: j['stato'] as String?,
    externalId: j['externalId'] as String?,
  );
}

/// A product under assistance (an asset) of a customer in this payload. [locationId] is NOT
/// nullable — the server's `SyncProdottoAssistenzaDto` declares `Guid LocationId`.
class ProdottoAssistenzaSyncDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String name;
  final String customerId;
  final String locationId;
  final bool isActive;
  final String? codice;
  final String? serialNumber;
  final String? categoria;
  final String? marchio;
  final String? externalId;

  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'createdAt',
    'updatedAt',
    'name',
    'customerId',
    'locationId',
    'isActive',
    'codice',
    'serialNumber',
    'categoria',
    'marchio',
    'externalId',
  };

  const ProdottoAssistenzaSyncDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.name,
    required this.customerId,
    required this.locationId,
    this.isActive = true,
    this.codice,
    this.serialNumber,
    this.categoria,
    this.marchio,
    this.externalId,
  });

  factory ProdottoAssistenzaSyncDto.fromJson(Map<String, dynamic> j) =>
      ProdottoAssistenzaSyncDto(
        id: j['id'] as String,
        tenantId: j['tenantId'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: _dt(j['updatedAt']),
        name: j['name'] as String,
        customerId: j['customerId'] as String,
        locationId: j['locationId'] as String,
        isActive: j['isActive'] as bool? ?? true,
        codice: j['codice'] as String?,
        serialNumber: j['serialNumber'] as String?,
        categoria: j['categoria'] as String?,
        marchio: j['marchio'] as String?,
        externalId: j['externalId'] as String?,
      );
}

/// An agent the payload's tickets reference — the manufacturer's or dealer's own service agent,
/// named on a ticket. Mirrored so the create wizard can offer one offline.
class AgentSyncDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String nome;
  final String? email;
  final String? cellulare;
  final bool isActive;

  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'createdAt',
    'updatedAt',
    'nome',
    'email',
    'cellulare',
    'isActive',
  };

  const AgentSyncDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.nome,
    this.email,
    this.cellulare,
    this.isActive = true,
  });

  factory AgentSyncDto.fromJson(Map<String, dynamic> j) => AgentSyncDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
    nome: j['nome'] as String,
    email: j['email'] as String?,
    cellulare: j['cellulare'] as String?,
    isActive: j['isActive'] as bool? ?? true,
  );
}

// ── Maintenance template ───────────────────────────────────────────────────────

/// One maintenance checklist template a technician may attach to a new ticket as its checklist —
/// the "Modello checklist" the web ticket form offers. Mirrors `SyncMaintenanceTemplateDto`; the
/// `MaintenanceTemplates` table's own doc comment records why the mirror is exactly these six fields.
class SyncMaintenanceTemplateDto {
  final String id;

  /// MaintenanceTemplateOrigin: "System" (curated) | "Tenant" (this tenant's own). Kept as the wire
  /// string rather than parsed to an enum — nothing on the device branches on it.
  final String origin;
  final String name;
  final String? description;
  final bool isActive;

  /// The version a new ticket would resolve to today, or null while every version is a draft or
  /// already retired. Null is a real state, not missing data.
  final int? latestPublishedVersion;

  static const Set<String> wireKeys = {
    'id',
    'origin',
    'name',
    'description',
    'isActive',
    'latestPublishedVersion',
  };

  const SyncMaintenanceTemplateDto({
    required this.id,
    required this.origin,
    required this.name,
    this.description,
    this.isActive = true,
    this.latestPublishedVersion,
  });

  factory SyncMaintenanceTemplateDto.fromJson(Map<String, dynamic> j) =>
      SyncMaintenanceTemplateDto(
        id: j['id'] as String,
        origin: j['origin'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        isActive: j['isActive'] as bool? ?? true,
        latestPublishedVersion: _intOrNull(j['latestPublishedVersion']),
      );

  /// Serializes back to the wire shape. The device only ever READS this DTO; `toJson` exists so a
  /// test can round-trip its own fixture through the exact keys `fromJson` reads.
  Map<String, dynamic> toJson() => {
    'id': id,
    'origin': origin,
    'name': name,
    'description': description,
    'isActive': isActive,
    'latestPublishedVersion': latestPublishedVersion,
  };
}

// ── Report aggregate (O-8a) ───────────────────────────────────────────────────
//
// The child rows of a report, plus its version and its files. Five classes, one per backend
// `SyncReport*Dto`; every one of them is a straight wire mirror — no device-side interpretation,
// because the same values already exist in these tables for reports authored here
// (`ReportStaffTable`, `ReportMateriali`, `ReportControlli`, `ReportAllegati`), and the point of
// the mirror is that the two origins become indistinguishable to every reader.

/// One technician's line on a report: hours, kilometres, vehicle and pause.
class SyncReportStaffDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String reportId;
  final String userId;
  final double? hoursWorked;
  final double kmTraveled;
  final String? vehicle;
  final double? costPerKm;
  final String? notes;
  final DateTime? startTime;
  final DateTime? endTime;
  final int pauseMinutes;

  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'createdAt',
    'updatedAt',
    'reportId',
    'userId',
    'hoursWorked',
    'kmTraveled',
    'vehicle',
    'costPerKm',
    'notes',
    'startTime',
    'endTime',
    'pauseMinutes',
  };

  const SyncReportStaffDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.reportId,
    required this.userId,
    this.hoursWorked,
    this.kmTraveled = 0,
    this.vehicle,
    this.costPerKm,
    this.notes,
    this.startTime,
    this.endTime,
    this.pauseMinutes = 0,
  });

  factory SyncReportStaffDto.fromJson(Map<String, dynamic> j) =>
      SyncReportStaffDto(
        id: j['id'] as String,
        tenantId: j['tenantId'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: _dt(j['updatedAt']),
        reportId: j['reportId'] as String,
        userId: j['userId'] as String,
        hoursWorked: _dbl(j['hoursWorked']),
        kmTraveled: _dbl(j['kmTraveled']) ?? 0,
        vehicle: j['vehicle'] as String?,
        costPerKm: _dbl(j['costPerKm']),
        notes: j['notes'] as String?,
        startTime: _dt(j['startTime']),
        endTime: _dt(j['endTime']),
        pauseMinutes: _intOrNull(j['pauseMinutes']) ?? 0,
      );
}

/// One material used on a report — either a catalogue reference or free text.
class SyncReportMaterialeDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String reportId;
  final String? materialeId;
  final String? freeTextName;
  final double quantity;
  final String? unitOfMeasure;
  final double? unitPrice;
  final String? notes;
  final String? magazzinoId;

  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'createdAt',
    'updatedAt',
    'reportId',
    'materialeId',
    'freeTextName',
    'quantity',
    'unitOfMeasure',
    'unitPrice',
    'notes',
    'magazzinoId',
  };

  const SyncReportMaterialeDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.reportId,
    this.materialeId,
    this.freeTextName,
    required this.quantity,
    this.unitOfMeasure,
    this.unitPrice,
    this.notes,
    this.magazzinoId,
  });

  factory SyncReportMaterialeDto.fromJson(Map<String, dynamic> j) =>
      SyncReportMaterialeDto(
        id: j['id'] as String,
        tenantId: j['tenantId'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: _dt(j['updatedAt']),
        reportId: j['reportId'] as String,
        materialeId: j['materialeId'] as String?,
        freeTextName: j['freeTextName'] as String?,
        quantity: _dbl(j['quantity']) ?? 0,
        unitOfMeasure: j['unitOfMeasure'] as String?,
        unitPrice: _dbl(j['unitPrice']),
        notes: j['notes'] as String?,
        magazzinoId: j['magazzinoId'] as String?,
      );
}

/// One answered checklist item on a report. `ticketControlId` is the wire's name for what
/// `ReportControlli` stores as `controlId` — the Drift column keeps its own name.
class SyncReportControlloDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String reportId;
  final String ticketControlId;
  final String? stringValue;
  final bool? boolValue;
  final DateTime? dateValue;
  final double? numberValue;
  final String? note;

  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'createdAt',
    'updatedAt',
    'reportId',
    'ticketControlId',
    'stringValue',
    'boolValue',
    'dateValue',
    'numberValue',
    'note',
  };

  const SyncReportControlloDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.reportId,
    required this.ticketControlId,
    this.stringValue,
    this.boolValue,
    this.dateValue,
    this.numberValue,
    this.note,
  });

  factory SyncReportControlloDto.fromJson(Map<String, dynamic> j) =>
      SyncReportControlloDto(
        id: j['id'] as String,
        tenantId: j['tenantId'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: _dt(j['updatedAt']),
        reportId: j['reportId'] as String,
        ticketControlId: j['ticketControlId'] as String,
        stringValue: j['stringValue'] as String?,
        boolValue: j['boolValue'] as bool?,
        dateValue: _dt(j['dateValue']),
        numberValue: _dbl(j['numberValue']),
        note: j['note'] as String?,
      );
}

/// One attachment, for a report OR a ticket. `entityType`/`entityId` say which, and they are the
/// only keys that matter: `report_allegati` has never had a report column.
class SyncReportAllegatoDto {
  final String id;
  final String tenantId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// AllegatoEntityTypeEnum: 0 = Ticket, 1 = Report, 2 = Materiale. Sent as the enum's ordinal.
  final int entityType;
  final String entityId;
  final String fileName;
  final String contentType;
  final int sizeBytes;

  /// AllegatoKindEnum: 0 = UserUpload, 1 = SystemArtifact (captured signatures).
  final int kind;
  final String uploadedByUserId;
  final bool isActive;

  /// SHA-256 of the bytes, lowercase hex. Null on rows written before the column existed.
  final String? contentHash;

  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'createdAt',
    'updatedAt',
    'entityType',
    'entityId',
    'fileName',
    'contentType',
    'sizeBytes',
    'kind',
    'uploadedByUserId',
    'isActive',
    'contentHash',
  };

  const SyncReportAllegatoDto({
    required this.id,
    required this.tenantId,
    required this.createdAt,
    this.updatedAt,
    required this.entityType,
    required this.entityId,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.kind,
    required this.uploadedByUserId,
    this.isActive = true,
    this.contentHash,
  });

  factory SyncReportAllegatoDto.fromJson(Map<String, dynamic> j) =>
      SyncReportAllegatoDto(
        id: j['id'] as String,
        tenantId: j['tenantId'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: _dt(j['updatedAt']),
        entityType: _intOrNull(j['entityType']) ?? 0,
        entityId: j['entityId'] as String,
        fileName: j['fileName'] as String,
        contentType: j['contentType'] as String,
        sizeBytes: _intOrNull(j['sizeBytes']) ?? 0,
        kind: _intOrNull(j['kind']) ?? 0,
        uploadedByUserId: j['uploadedByUserId'] as String,
        isActive: j['isActive'] as bool? ?? true,
        contentHash: j['contentHash'] as String?,
      );
}

/// The version of one report's server row (`xmin`), as `GET /api/reports/{id}` reports it.
class SyncReportVersionDto {
  final String reportId;
  final String version;

  static const Set<String> wireKeys = {'reportId', 'version'};

  const SyncReportVersionDto({required this.reportId, required this.version});

  factory SyncReportVersionDto.fromJson(Map<String, dynamic> j) =>
      SyncReportVersionDto(
        reportId: j['reportId'] as String,
        version: j['version'] as String,
      );
}

/// One ticket timer session the caller owns, as the server holds it (O-9).
///
/// Mirrors `SyncTicketWorkLogDto` on the backend. `workDate` + `startTime`/`endTime` are the
/// Rome-local frame every ticket worklog reader uses; `startUtc`/`endUtc` are the true instants and
/// are null on rows the backend wrote before it recorded them. Durations must prefer the instants:
/// subtracting two bare times of day gives a negative number for an overnight session.
class SyncTicketWorkLogDto {
  final String id;
  final String tenantId;
  final String ticketId;
  final String userId;
  final DateTime workDate;
  final Duration startTime;
  final Duration? endTime;
  final DateTime? startUtc;
  final DateTime? endUtc;

  /// `WorkLogApprovalStatusEnum` ordinal: 0 Draft, 1 Submitted, 2 Approved, 3 Rejected.
  final int approvalStatus;
  final String? description;
  final bool isManualEntry;

  /// The device's own id for this session, when it was born on a phone; null for a row created in
  /// the office or by the online start/stop pair. Lets the device recognise the server row of a
  /// session it may still be holding in its own queue.
  final String? clientId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'ticketId',
    'userId',
    'workDate',
    'startTime',
    'endTime',
    'startUtc',
    'endUtc',
    'approvalStatus',
    'description',
    'isManualEntry',
    'clientId',
    'createdAt',
    'updatedAt',
  };

  const SyncTicketWorkLogDto({
    required this.id,
    required this.tenantId,
    required this.ticketId,
    required this.userId,
    required this.workDate,
    required this.startTime,
    this.endTime,
    this.startUtc,
    this.endUtc,
    this.approvalStatus = 0,
    this.description,
    this.isManualEntry = false,
    this.clientId,
    required this.createdAt,
    this.updatedAt,
  });

  factory SyncTicketWorkLogDto.fromJson(Map<String, dynamic> j) =>
      SyncTicketWorkLogDto(
        id: j['id'] as String,
        tenantId: j['tenantId'] as String,
        ticketId: j['ticketId'] as String,
        userId: j['userId'] as String,
        workDate: parseDateOnlyOrThrow(j['workDate']),
        startTime: parseTimeSpan(j['startTime']) ?? Duration.zero,
        endTime: j['endTime'] == null ? null : parseTimeSpan(j['endTime']),
        startUtc: _dt(j['startUtc']),
        endUtc: _dt(j['endUtc']),
        approvalStatus: _intOrNull(j['approvalStatus']) ?? 0,
        description: j['description'] as String?,
        isManualEntry: j['isManualEntry'] as bool? ?? false,
        clientId: j['clientId'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: _dt(j['updatedAt']),
      );
}

/// One cantiere clock-in/clock-out of the signed-in technician, as the server holds it.
///
/// Mirrors `SyncCantiereWorkLogDto` on the backend. `workDate` + `startTime`/`endTime` are the
/// Rome-local values the WorkLogs domain stores; `startUtc`/`endUtc` are the true instants and are
/// null on legacy rows — prefer them for a duration, because subtracting a time-of-day pair across
/// midnight is negative.
///
/// Only the caller's own punches ever arrive here. A lead's team hours stay an online read, the
/// same rule `SyncTicketWorkLogDto` follows.
class SyncCantiereWorkLogDto {
  final String id;
  final String tenantId;
  final String cantiereId;
  final String userId;
  final String? ticketId;
  final DateTime workDate;
  final Duration startTime;
  final Duration? endTime;
  final DateTime? startUtc;
  final DateTime? endUtc;

  /// `CantiereWorkLogTypeEnum`: 0 Site, 1 Travel, 2 Setup.
  final int workLogType;

  /// `WorkLogApprovalStatusEnum`: 0 Draft, 1 Submitted, 2 Approved, 3 Rejected.
  final int approvalStatus;
  final String? description;

  /// The device's own key for the punch, when it queued one — what lets the screen recognise the
  /// server's row of a shift it is still holding in the outbox.
  final String? clientId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'cantiereId',
    'userId',
    'ticketId',
    'workDate',
    'startTime',
    'endTime',
    'startUtc',
    'endUtc',
    'workLogType',
    'approvalStatus',
    'description',
    'clientId',
    'createdAt',
    'updatedAt',
  };

  const SyncCantiereWorkLogDto({
    required this.id,
    required this.tenantId,
    required this.cantiereId,
    required this.userId,
    this.ticketId,
    required this.workDate,
    required this.startTime,
    this.endTime,
    this.startUtc,
    this.endUtc,
    this.workLogType = 0,
    this.approvalStatus = 0,
    this.description,
    this.clientId,
    required this.createdAt,
    this.updatedAt,
  });

  factory SyncCantiereWorkLogDto.fromJson(Map<String, dynamic> j) => SyncCantiereWorkLogDto(
    id: j['id'] as String,
    tenantId: j['tenantId'] as String,
    cantiereId: j['cantiereId'] as String,
    userId: j['userId'] as String,
    ticketId: j['ticketId'] as String?,
    workDate: parseDateOnlyOrThrow(j['workDate']),
    startTime: parseTimeSpan(j['startTime']) ?? Duration.zero,
    endTime: j['endTime'] == null ? null : parseTimeSpan(j['endTime']),
    startUtc: _dt(j['startUtc']),
    endUtc: _dt(j['endUtc']),
    workLogType: _intOrNull(j['workLogType']) ?? 0,
    approvalStatus: _intOrNull(j['approvalStatus']) ?? 0,
    description: j['description'] as String?,
    clientId: j['clientId'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: _dt(j['updatedAt']),
  );
}

/// One recorded change of one ticket, as the server holds it.
///
/// Mirrors `SyncTicketHistoryDto` on the backend. `oldValue`/`newValue` are the server's RAW,
/// invariant text — ids as `D` GUIDs, instants as round-trip `O` — never a rendered label, because
/// the timeline resolves them through the mirrors this device already holds (a status id to the
/// status name in the tenant's language). Storing labels would freeze a translation at write time
/// and lie after a rename.
///
/// [changedByUserId] is empty for a change no person made (a background job, the customer portal);
/// the screen says so instead of guessing a colleague.
class SyncTicketHistoryDto {
  final String id;
  final String tenantId;
  final String ticketId;

  /// The ticket property name (`StatusId`, `AssignedUserId`, …). Unknown names are still shown
  /// with their raw value rather than dropped.
  final String fieldName;
  final String? oldValue;
  final String? newValue;
  final String changedByUserId;
  final DateTime changedAt;

  static const Set<String> wireKeys = {
    'id',
    'tenantId',
    'ticketId',
    'fieldName',
    'oldValue',
    'newValue',
    'changedByUserId',
    'changedAt',
  };

  const SyncTicketHistoryDto({
    required this.id,
    required this.tenantId,
    required this.ticketId,
    required this.fieldName,
    this.oldValue,
    this.newValue,
    required this.changedByUserId,
    required this.changedAt,
  });

  factory SyncTicketHistoryDto.fromJson(Map<String, dynamic> j) =>
      SyncTicketHistoryDto(
        id: j['id'] as String,
        tenantId: j['tenantId'] as String,
        ticketId: j['ticketId'] as String,
        fieldName: j['fieldName'] as String? ?? '',
        oldValue: j['oldValue'] as String?,
        newValue: j['newValue'] as String?,
        changedByUserId: j['changedByUserId'] as String? ?? '',
        // The instant the change was recorded. `_dt` parses the server's `Z` instant; Drift hands
        // it back later as a LOCAL-kind value, so readers re-stamp it to UTC before comparing.
        changedAt: _dt(j['changedAt']) ?? DateTime.now().toUtc(),
      );
}

// ── Helpers ────────────────────────────────────────────────────────────────────
DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String);

/// `int32` may arrive as a JSON number or a numeric string (see checklist_sync_dto.dart). Unlike
/// `_int`, an unparseable value here returns null rather than 0: 0 is a real contract type.
int? _intOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

double? _dbl(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) fromJson) {
  if (v == null) return [];
  return (v as List).map((e) => fromJson(e as Map<String, dynamic>)).toList();
}
