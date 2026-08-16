// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/theme/app_rack.dart';
import '../../core/widgets/widgets.dart';
import '../../data/gdpr/gdpr_api_client.dart';
import '../../data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

// ══════════════════════════════════════════════════════════════════════════════
// I miei dati
//
// The subject-access surface. The backend has served `/api/Gdpr/consent`,
// `/api/Gdpr/export` and `DELETE /api/Gdpr/account` since before this app
// shipped, and `lib/` referenced none of them: a technician who only ever used
// the phone could not find out what was recorded about them, and the most
// revealing category — the GPS trail on cantiere timbrature — was the one
// least likely to be guessed from the outside.
//
// This screen states what is held, in categories and counts, in the order that
// matters to the person reading it. It does not offer deletion (see
// gdpr_api_client.dart) and it does not pretend to be the machine-readable
// copy: it says where that comes from instead of implying the phone is the
// whole of the right.
// ══════════════════════════════════════════════════════════════════════════════

class IMieiDatiScreen extends ConsumerWidget {
  const IMieiDatiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(personalDataSummaryProvider);
    final isOnline = ref.watch(isOnlineProvider);

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: 'I miei dati', showBack: true),
            Expanded(
              child: !isOnline
                  // Not an error and not a retry loop: this screen is the server's statement about
                  // itself, so with no signal there is nothing honest to draw. Saying so beats a
                  // spinner that will never resolve.
                  ? const UnavailableState(
                      icon: LucideIcons.wifiOff,
                      titolo: 'Serve la connessione',
                      motivo:
                          'Questi dati vengono letti dal server nel momento in cui li apri, così '
                          'sono quelli veri e non una copia vecchia. Riprova quando hai segnale.',
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(personalDataSummaryProvider);
                        ref.invalidate(consentStatusProvider);
                      },
                      child: summary.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => const UnavailableState(
                          titolo: 'Dati non consultabili ora',
                          motivo:
                              'Il server non ha risposto. Riprova tra qualche minuto: nessuno dei '
                              'tuoi dati è stato modificato.',
                        ),
                        data: (data) => _Body(summary: data),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.summary});

  final PersonalDataSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = summary.identity;

    return ListView(
      padding: EdgeInsets.fromLTRB(19, 8, 19, context.navClearance),
      children: [
        _Preamble(exportDate: summary.exportDate),
        const SizedBox(height: 20),

        if (identity != null) ...[
          StepLabel(title: 'La tua anagrafica'),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                KeyVal(label: 'Nome', value: identity.fullName ?? '—'),
                KeyVal(label: 'Email', value: identity.email ?? '—'),
                KeyVal(label: 'Telefono', value: identity.phone ?? '—'),
                KeyVal(label: 'Matricola', value: identity.staffCode ?? '—'),
                KeyVal(
                  label: 'Account creato',
                  value: _date(identity.createdAt),
                  showDivider: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        StepLabel(title: 'Cosa è registrato su di te'),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < summary.categories.length; i++)
                _CategoryRow(
                  category: summary.categories[i],
                  showDivider: i < summary.categories.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        StepLabel(title: 'Consensi'),
        const SizedBox(height: 8),
        const _ConsentBlock(),
        const SizedBox(height: 24),

        const _RightsBlock(),
      ],
    );
  }

  static String _date(DateTime? value) =>
      value == null ? '—' : DateFormat('d MMMM y', 'it').format(value);
}

// ── Preamble ──────────────────────────────────────────────────────────────────

class _Preamble extends StatelessWidget {
  const _Preamble({required this.exportDate});

  final DateTime? exportDate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Questo è tutto ciò che la tua azienda ha registrato su di te in TaskTap.',
          style: TextStyle(fontFamily: 'Manrope', fontSize: 14, height: 1.45, color: c.ink),
        ),
        if (exportDate != null) ...[
          const SizedBox(height: 6),
          Text(
            'Letto dal server il ${DateFormat('d MMMM y \'alle\' HH:mm', 'it').format(exportDate!)}.',
            style: TextStyle(fontFamily: 'Manrope', fontSize: 12, color: c.inkMuted),
          ),
        ],
      ],
    );
  }
}

// ── One category ──────────────────────────────────────────────────────────────

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.showDivider});

  final DataCategory category;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = category.count;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      category.label,
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    if (category.nota != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        category.nota!,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 12,
                          height: 1.35,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // "—" rather than "0" when the server omitted the category: zero is a claim that
              // nothing of this kind is held, and we were not told that.
              Text(
                count?.toString() ?? '—',
                semanticsLabel: count == null
                    ? '${category.label}: numero non comunicato dal server'
                    : '${category.label}: $count',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: count == null ? c.inkMuted : c.ink,
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, thickness: 1, color: c.borderLight),
      ],
    );
  }
}

// ── Consents ──────────────────────────────────────────────────────────────────

/// Read-only, deliberately.
///
/// `POST /api/Gdpr/consent` takes a free-string `consentType` and nothing in either codebase
/// enumerates the valid values. A toggle here would write a guess into a record whose whole purpose
/// is to be legally reliable.
class _ConsentBlock extends ConsumerWidget {
  const _ConsentBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consents = ref.watch(consentStatusProvider);

    return consents.when(
      loading: () => const AppCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ),
      error: (e, _) => AppCard(
        child: Text(
          'Elenco consensi non disponibile in questo momento.',
          style: TextStyle(fontFamily: 'Manrope', fontSize: 13, color: context.colors.inkMuted),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return AppCard(
            child: Text(
              'Nessun consenso risulta registrato a tuo nome.',
              style: TextStyle(fontFamily: 'Manrope', fontSize: 13, color: context.colors.inkMuted),
            ),
          );
        }
        return AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < list.length; i++)
                KeyVal(
                  label: list[i].consentType,
                  value: list[i].granted
                      ? 'Dato${_on(list[i].grantedAt)}'
                      : 'Non dato${_on(list[i].grantedAt)}',
                  showDivider: i < list.length - 1,
                ),
            ],
          ),
        );
      },
    );
  }

  static String _on(DateTime? at) =>
      at == null ? '' : ' il ${DateFormat('d/M/y', 'it').format(at)}';
}

// ── Where the rest of the right is exercised ──────────────────────────────────

/// The part the phone cannot do, said plainly rather than left as a missing button.
///
/// Deletion is absent by decision, not by omission: the endpoint anonymises the user and
/// deactivates them, and on a company handset that destroys an identity payroll and invoicing run
/// on. Someone finding no delete button and no explanation would reasonably conclude the app is
/// hiding the right; this states who to ask.
class _RightsBlock extends StatelessWidget {
  const _RightsBlock();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.bg3,
        border: Border.all(color: c.borderLight),
        borderRadius: AppRack.freeShape,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.shieldCheck, size: 18, color: c.inkMuted),
              const SizedBox(width: 8),
              Text(
                'Correggere o cancellare',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Per far correggere un dato sbagliato, per ottenere una copia completa in formato '
            'elettronico, o per chiedere la cancellazione del tuo account, rivolgiti '
            'all\'amministrazione della tua azienda. Da qui non si cancella: il tuo account è '
            'collegato a buste paga e fatture già emesse.',
            style: TextStyle(fontFamily: 'Manrope', fontSize: 13, height: 1.45, color: c.inkMuted),
          ),
        ],
      ),
    );
  }
}
