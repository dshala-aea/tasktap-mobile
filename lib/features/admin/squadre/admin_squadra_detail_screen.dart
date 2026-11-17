// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/auth/access.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/detail/detail_hero.dart';
import '../../../core/widgets/detail/detail_link_row.dart';
import '../../../core/widgets/detail/detail_scaffold.dart';
import '../../../core/widgets/detail/detail_section.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/entitlements/entitlement_providers.dart';
import '../../../data/sync/connectivity_provider.dart';
import '../../../data/users/user_directory.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../admin_api_client.dart';

/// Fetches squadra detail with membri from backend API.
final adminSquadraDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>(
  (ref, id) async {
    final api = ref.watch(adminApiClientProvider);
    return api.fetchSquadraDetail(id);
  },
);

/// Admin squadra detail — the wave-0 summary shell.
///
/// Hero + `Modifica`, then Relazioni (membri) → Sintesi (descrizione, note). The prototype's
/// Attività section is the squadra's active cantieri, and nothing on the device (or in
/// `/api/squadre`) carries a squadra → cantiere relation, so that section is hidden rather than
/// inventing a count. Empty sections are hidden by the shell, and the hero owns `Modifica`, so
/// there is no FAB.
class AdminSquadraDetailScreen extends ConsumerWidget {
  const AdminSquadraDetailScreen({super.key, required this.squadra});

  final Map<String, dynamic> squadra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = _clean(squadra['id']);

    if (id == null) {
      // The route carries the squadra as `extra`; a deep link without it has no id to fetch.
      return const DetailScaffold.unavailable(
        screenTitle: 'Squadra',
        icon: LucideIcons.users,
        title: 'Squadra non disponibile',
        reason: "Apri la squadra dall'elenco per vederne i dettagli.",
      );
    }

    final detailAsync = ref.watch(adminSquadraDetailProvider(id));
    final online = ref.watch(isOnlineProvider);

    return detailAsync.when(
      loading: () => const DetailScaffold.loading(screenTitle: 'Squadra'),
      error: (e, _) => DetailScaffold.unavailable(
        screenTitle: 'Squadra',
        icon: online ? LucideIcons.alertTriangle : LucideIcons.wifiOff,
        title: online ? 'Squadra non disponibile' : 'Squadre non disponibili offline',
        reason: online
            ? 'Non è stato possibile caricare i dati della squadra. Riprova.'
            : 'Le squadre si leggono con la connessione: non vengono scaricate sul dispositivo.',
        onRetry: () => ref.invalidate(adminSquadraDetailProvider(id)),
      ),
      data: (detail) {
        // GET /api/squadre/{id} wraps the squadra's own fields under a "squadra" key
        // (backend record SquadraDetailResponse(Squadra Squadra, List<SquadraMembro> Membri) —
        // see SquadraDetailResponse.cs), with "membri" as the sibling key holding the member
        // list. The `?? squadra` fallback is the flat row the list screen already has in hand
        // (`extra: squadra` in admin_squadra_list_screen.dart) — no such wrapper there.
        final data = (detail?['squadra'] as Map<String, dynamic>?) ?? squadra;
        final membri = (detail?['membri'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        return _SquadraDetailBody(squadra: data, membri: membri, squadraId: id);
      },
    );
  }
}

class _SquadraDetailBody extends ConsumerWidget {
  const _SquadraDetailBody({required this.squadra, required this.membri, required this.squadraId});

  final Map<String, dynamic> squadra;
  final List<Map<String, dynamic>> membri;
  final String squadraId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nome = _clean(squadra['nome']) ?? 'Squadra';
    final descrizione = _clean(squadra['descrizione']);
    final specializzazione = _clean(squadra['specializzazione']);
    final note = _clean(squadra['note']);
    final isActive = squadra['isActive'] as bool? ?? true;
    final canWrite = capabilityHeld(
      ref.watch(cachedEntitlementProvider).value,
      'team.squadra.write',
    );
    // `/altro/pianificazioni` requires `pianificazione.schedule.read`; without it the header
    // action would only dead-end at /forbidden, so it is withheld rather than left actionable.
    final canReadSchedule = capabilityHeld(
      ref.watch(cachedEntitlementProvider).value,
      'pianificazione.schedule.read',
    );

    // One bulk fetch shared by the whole screen (the same one the list screen uses), never a
    // per-member `/api/users/{id}` call. `squadraId` is the derived field
    // UsersController.PopulateSquadreAsync projects onto every user response.
    final usersAsync = ref.watch(allUsersProvider(true));
    final usersById = <String, Map<String, dynamic>>{
      for (final u in usersAsync.value ?? const <Map<String, dynamic>>[]) u['id'] as String: u,
    };
    // The local colleagues mirror is only the fallback for a user the bulk fetch has already
    // answered for; reading it while that fetch is still in flight would open the database for a
    // name the bulk response is about to provide anyway.
    final allowLocalNameFallback = usersAsync.hasValue || usersAsync.hasError;

    final members = _sortedMembers(membri);
    final leadName =
        _clean(squadra['capSquadraNome']) ??
        _leadNameFromMembers(members, usersById, ref, allowLocalNameFallback);

    // The prototype's hero line is `lead · N membri · N cantieri`. No cantiere association exists,
    // so the squadra's own specializzazione keeps the third slot instead of inventing a number.
    final heroFacts = [
      if (leadName != null) 'Lead $leadName',
      _membriLabel(members.length),
      ?specializzazione,
    ].join(' · ');

    // No hero fact is repeated here: lead, member count and specializzazione stay above the fold,
    // and Sintesi carries only the free text the prototype names.
    final hasSintesi = descrizione != null || note != null;

    return DetailScaffold(
      screenTitle: 'Squadra',
      headerActions: [
        // Keep the existing pre-filtered pianificazioni link: the list screen opens this same
        // route with the squadra id as `extra`.
        if (canReadSchedule)
          HeaderIconBtn(
            icon: LucideIcons.calendarDays,
            label: 'Pianificazioni squadra',
            glass: true,
            onTap: () => context.push('/altro/pianificazioni', extra: squadraId),
          ),
        if (canWrite)
          HeaderIconBtn(
            icon: LucideIcons.userPlus,
            label: 'Aggiungi membro',
            glass: true,
            onTap: () => _showAddMemberSheet(context, ref),
          ),
      ],
      hero: DetailHeroData(
        variant: DetailHeroVariant.summary,
        kind: 'Summary · squadra',
        kicker: 'Summary · squadra',
        title: nome,
        status: isActive
            ? const DetailStatus(label: 'Attiva', tone: DetailStatusTone.good)
            : const DetailStatus(label: 'Inattiva', tone: DetailStatusTone.bad),
        subtitle: heroFacts.isEmpty ? null : heroFacts,
        primaryAction: DetailAction(
          label: 'Modifica',
          enabled: canWrite,
          disabledReason: canWrite ? null : noPermissionReason,
          onPressed: () async {
            // Awaited so a saved edit is reflected the moment the admin pops back here —
            // without this, the fire-and-forget push left the hero showing pre-edit values
            // until the admin left and re-entered the screen.
            await context.push<bool>('/altro/squadre/$squadraId/modifica', extra: squadra);
            ref.invalidate(adminSquadraDetailProvider(squadraId));
          },
        ),
      ),
      sections: [
        DetailSectionData(
          title: 'Relazioni',
          trailing: DetailSectionMeta(_membriLabel(members.length)),
          isEmpty: members.isEmpty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < members.length; i++)
                _MemberRow(
                  membro: members[i],
                  user: usersById[members[i]['userId'] as String? ?? ''],
                  allowLocalNameFallback: allowLocalNameFallback,
                  showDivider: i < members.length - 1,
                  onRemove: canWrite ? () => _removeMember(context, members[i]) : null,
                ),
            ],
          ),
        ),
        DetailSectionData(
          title: 'Sintesi',
          isEmpty: !hasSintesi,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (descrizione != null) _TextBlock(label: 'Descrizione', value: descrizione),
              if (descrizione != null && note != null) const SizedBox(height: AppSpacing.base),
              if (note != null) _TextBlock(label: 'Note', value: note),
            ],
          ),
        ),
      ],
    );
  }

  /// The lead's display name, when `capSquadraNome` is absent but the membership list still names
  /// a `Capo` row. The server derives the former; this is only the fallback.
  String? _leadNameFromMembers(
    List<Map<String, dynamic>> members,
    Map<String, Map<String, dynamic>> usersById,
    WidgetRef ref,
    bool allowLocalNameFallback,
  ) {
    for (final member in members) {
      if (member['ruolo'] != SquadraRuolo.capo) continue;
      final userId = member['userId'] as String? ?? '';
      if (userId.isEmpty) continue;
      return _memberName(userId, usersById[userId], ref, allowLocalNameFallback);
    }
    return null;
  }

  /// Lead first, then the rest in server order — the prototype reads "membri, lead".
  List<Map<String, dynamic>> _sortedMembers(List<Map<String, dynamic>> members) {
    final lead = members.where((m) => m['ruolo'] == SquadraRuolo.capo);
    final rest = members.where((m) => m['ruolo'] != SquadraRuolo.capo);
    return [...lead, ...rest];
  }

  Future<void> _removeMember(BuildContext context, Map<String, dynamic> membro) async {
    final userId = membro['userId'] as String? ?? '';
    if (userId.isEmpty) return;

    final confirmed = await confirmDeleteDialog(
      context,
      title: 'Rimuovi membro',
      message: 'Vuoi rimuovere questo membro dalla squadra?',
      confirmLabel: 'Rimuovi',
    );
    if (confirmed && context.mounted) {
      try {
        final container = ProviderScope.containerOf(context);
        final api = container.read(adminApiClientProvider);
        await api.removeSquadraMember(squadraId, userId);
        // Without this, the member list keeps showing the just-removed row until the admin
        // leaves and re-enters this screen — nothing else refetches adminSquadraDetailProvider.
        container.invalidate(adminSquadraDetailProvider(squadraId));
        if (context.mounted) {
          showAppToast(context, message: 'Membro rimosso', tone: ToastTone.success);
        }
      } catch (e) {
        if (context.mounted) {
          showAppToast(context, message: 'Impossibile salvare. Riprova.', tone: ToastTone.error);
        }
      }
    }
  }

  void _showAddMemberSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddMemberSheet(squadraId: squadraId, api: ref.read(adminApiClientProvider)),
    );
  }
}

/// One member row: name on the left, role/last access plus the remove control on the right.
class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.membro,
    required this.user,
    required this.allowLocalNameFallback,
    required this.showDivider,
    required this.onRemove,
  });

  final Map<String, dynamic> membro;
  final Map<String, dynamic>? user;
  final bool allowLocalNameFallback;
  final bool showDivider;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = membro['userId'] as String? ?? '';
    final name = userId.isEmpty
        ? 'Membro non sincronizzato'
        : _memberName(userId, user, ref, allowLocalNameFallback);
    final ruolo = _ruoloLabel(membro['ruolo']);
    // Only claim "Mai" (never) when the bulk fetch actually resolved this user and found no
    // access timestamp — a userId absent from the fetch (page-size cap, deactivated, or not yet
    // loaded) is unknown, not "never accessed", so the row falls back to just the role.
    final meta = user == null
        ? ruolo
        : '$ruolo · Ultimo accesso: ${_formatLastAccess(user!['lastAccessAt'] as String?)}';

    return DetailLinkRow(
      title: name,
      showDivider: showDivider,
      trailing: _MemberTrailing(meta: meta, onRemove: onRemove),
    );
  }
}

class _MemberTrailing extends StatelessWidget {
  const _MemberTrailing({required this.meta, required this.onRemove});

  final String meta;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(
            meta.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppTextStyles.docCode.copyWith(
              fontSize: 7.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
              color: context.colors.inkMuted,
            ),
          ),
        ),
        const SizedBox(width: 2),
        if (onRemove != null)
          IconButton(
            icon: const Icon(LucideIcons.userMinus, size: 18),
            tooltip: 'Rimuovi dalla squadra',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
          ),
      ],
    );
  }
}

/// Long free text under a section: a mono label above wrapped prose.
class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.docCode.copyWith(
            fontSize: 8,
            letterSpacing: 0.64,
            color: colors.inkMuted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: AppTextStyles.bodySmall.copyWith(fontSize: 11.5, height: 1.4, color: colors.ink),
        ),
      ],
    );
  }
}

/// Resolves a member's display name from the one bulk users fetch, falling back to the synced
/// colleagues mirror only when that fetch has no name for them (or does not know the id at all).
String _memberName(
  String userId,
  Map<String, dynamic>? user,
  WidgetRef ref,
  bool allowLocalNameFallback,
) {
  final bulkName = _userName(user);
  if (bulkName != null) return bulkName;
  if (!allowLocalNameFallback) return 'Membro non sincronizzato';
  final colleague = ref.watch(colleagueNameProvider(userId)).value;
  return _clean(colleague) ?? 'Membro non sincronizzato';
}

String? _userName(Map<String, dynamic>? user) {
  if (user == null) return null;
  final display = _clean(user['displayName']);
  if (display != null) return display;
  final full = _clean(user['fullName']);
  if (full != null) return full;
  final first = _clean(user['firstName']);
  final last = _clean(user['lastName']);
  final composed = [first, last].whereType<String>().join(' ').trim();
  return composed.isEmpty ? null : composed;
}

String _ruoloLabel(Object? ruolo) => ruolo == SquadraRuolo.capo ? 'Capo squadra' : 'Membro';

String _membriLabel(int count) => count == 1 ? '1 membro' : '$count membri';

/// Formats a `User.lastAccessAt` ISO timestamp (or its absence) for the member row — "Mai" for a
/// user who has never accessed the app (the field is `null`), otherwise the same absolute
/// `dd/MM/yyyy HH:mm` timestamp style this app already uses for other point-in-time fields
/// (`signedAt` in `rapportino_view_screen.dart`), converted to local time.
String _formatLastAccess(String? iso) {
  if (iso == null) return 'Mai';
  return DateFormat('dd/MM/yyyy HH:mm', 'it').format(DateTime.parse(iso).toLocal());
}

String? _clean(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

/// Bottom sheet to add a member to a squadra.
class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet({required this.squadraId, required this.api});

  final String squadraId;
  final AdminApiClient api;

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  String? _selectedUserId;
  int _ruolo = SquadraRuolo.membro;
  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      // Same population the squadra LIST screen uses (`allUsersProvider` above): every
      // active user in the tenant, no role filter. This picker previously called
      // `fetchTechnicians()` (`GET /api/users?role=Technician`), a client-side invention — the
      // backend does not restrict squadra membership by role (`SquadreController` validates the
      // member, no role rule), so the filter only hid valid members. That is why the operator
      // reported "si possono inserire solo paolo e daniel": an Office-only colleague simply never
      // appeared.
      //
      // Multi-role users are NOT the cause and must not be re-litigated as one: `UsersController.
      // GetAll` filters `u.Roles.Contains(role.Value)` over the user's whole role SET, so an
      // Office+Technician user already came back under role=Technician. The divergence between the
      // three surfaces answering "who can be a member" was the filter's existence, not its
      // multi-role handling — web's squadra control (`useUserLookup()`) and this app's own list
      // screen both fetch with no role filter. This now matches them.
      final users = await widget.api.fetchAllUsersWithSquadraInfo();
      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (_selectedUserId == null) return;
    setState(() => _isSaving = true);
    try {
      await widget.api.addSquadraMember(widget.squadraId, userId: _selectedUserId!, ruolo: _ruolo);
      if (mounted) {
        // Without this, the new member is invisible on the detail screen behind this sheet
        // until the admin leaves and re-enters it — nothing else refetches this provider.
        ProviderScope.containerOf(context).invalidate(adminSquadraDetailProvider(widget.squadraId));
        showAppToast(context, message: 'Membro aggiunto', tone: ToastTone.success);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Impossibile salvare. Riprova.', tone: ToastTone.error);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom +
            AppSpacing.pagePadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.md),
            child: SheetHandle(),
          ),
          Text('Aggiungi membro', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            AppFieldShell(
              label: 'Tecnico *',
              child: DropdownButtonFormField<String>(
                // ignore: deprecated_member_use — controlled field, needs value not initialValue
                value: _selectedUserId,
                items: _users
                    .map(
                      (t) => DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text(userDisplayName(t)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedUserId = v),
              ),
            ),
          const SizedBox(height: 16),
          AppFieldShell(
            label: 'Ruolo',
            // Backend `SquadraRuoloEnum` (WorkEnums.cs) only has Membro=0/Capo=1 — no "TeamLead"
            // value exists, so offering it here (as this dropdown used to) always fails
            // deserialization server-side. See SquadraRuolo in admin_api_client.dart.
            child: DropdownButtonFormField<int>(
              // ignore: deprecated_member_use — controlled field, needs value not initialValue
              value: _ruolo,
              items: const [
                DropdownMenuItem(value: SquadraRuolo.membro, child: Text('Membro')),
                DropdownMenuItem(value: SquadraRuolo.capo, child: Text('Capo squadra')),
              ],
              onChanged: (v) => setState(() => _ruolo = v ?? SquadraRuolo.membro),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: _isSaving ? 'Salvataggio…' : 'Aggiungi',
              onPressed: _isSaving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
