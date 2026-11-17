// dart format width=100
// lib/features/cantiere/cantiere_map_screen.dart
//
// The map-led cantiere view ("03 — la mappa") reachable from the detail's map card. Full-screen,
// interactive OpenStreetMap with the site pin, and the same day/primary-action card as the detail
// floating over it — so "where is it" and "am I on site" are answered on one surface.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/maps_launcher.dart';
import '../timbra/cantiere_timbra_screen.dart'
    show
        cantiereActiveSessionProvider,
        cantiereCrewAssignmentsProvider,
        cantiereTodayHoursProvider,
        formatHoursMinutes;
import 'cantiere_close_sheet.dart';
import 'cantiere_day.dart';
import 'cantiere_design.dart';
import 'cantiere_providers.dart';

const String _osmUserAgentPackageName = 'com.advantedge.tasktap.tasktap_mobile';

class CantiereMapScreen extends ConsumerWidget {
  const CantiereMapScreen({super.key, required this.cantiereId});

  final String cantiereId;

  static String _statusLabel(int status) => switch (status) {
    0 => 'Attivo',
    1 => 'Completato',
    2 => 'Annullato',
    _ => '—',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cantiere = ref.watch(cantiereByIdProvider(cantiereId)).value;
    final pointAsync = ref.watch(cantiereGeocodedLocationProvider(cantiereId));
    final active = ref.watch(cantiereActiveSessionProvider);
    final activeHere = active?.cantiereId == cantiereId;
    final todayHours = ref.watch(cantiereTodayHoursProvider(cantiereId));
    final crewCount = ref.watch(cantiereCrewAssignmentsProvider(cantiereId)).value?.length;

    final address = [
      cantiere?.address,
      cantiere?.city,
      cantiere?.postalCode,
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    return Scaffold(
      backgroundColor: context.colors.bg2,
      body: Stack(
        children: [
          Positioned.fill(
            child: pointAsync.when(
              loading: () =>
                  const _MapMessage(icon: LucideIcons.mapPin, message: 'Caricamento mappa…'),
              error: (e, _) => _MapMessage(
                icon: LucideIcons.mapPinOff,
                message: address.isEmpty ? 'Posizione non disponibile' : address,
              ),
              data: (point) => point == null
                  ? _MapMessage(
                      icon: LucideIcons.mapPinOff,
                      message: address.isEmpty ? 'Posizione non disponibile' : address,
                    )
                  : _CantiereMap(point: LatLng(point.lat, point.lng)),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SquareBackButton(onTap: () => context.pop()),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CantiereCard(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cantiere?.name ?? 'Cantiere',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: cantiereDisplay(context, 15),
                            ),
                            if (address.isNotEmpty)
                              Text(
                                address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: cantiereBody(context, 10, color: context.colors.inkMuted),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 12),
              child: CantiereCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CantiereStamp(
                          label: _statusLabel(cantiere?.status ?? 0),
                          color: (cantiere?.status ?? 0) == 0
                              ? context.colors.green
                              : context.colors.inkMuted,
                        ),
                        if (activeHere)
                          CantiereLiveElapsed(
                            start: active!.startTime,
                            clock: true,
                            style: cantiereTimer(context, size: 19),
                          )
                        else
                          Text(
                            formatHoursMinutes(todayHours),
                            style: cantiereTimer(
                              context,
                              size: 19,
                            ).copyWith(color: context.colors.ink),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 5, bottom: 12),
                      child: activeHere
                          ? CantiereHeroCopy(
                              before: 'Sei in cantiere dalle ',
                              bold: _hm(active!.startTime),
                              after: crewCount != null && crewCount > 0
                                  ? ' · squadra di $crewCount'
                                  : '',
                            )
                          : CantiereHeroCopy(
                              before: todayHours > Duration.zero
                                  ? 'Oggi su questo cantiere'
                                  : 'Pronto a timbrare',
                            ),
                    ),
                    if (activeHere)
                      CantiereButton(
                        label: 'Timbra uscita',
                        onPressed: () => showCantiereCloseSheet(
                          context,
                          cantiereId: cantiereId,
                          cantiereName: cantiere?.name ?? 'Cantiere',
                          startTime: active!.startTime,
                        ),
                      )
                    else
                      CantiereButton(
                        label: 'Timbra cantiere',
                        onPressed: () =>
                            context.push(AppRoutes.cantiereTimbraPath(cantiereId: cantiereId)),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: CantiereButton(
                            label: 'Indicazioni',
                            kind: CantiereButtonKind.secondary,
                            compact: true,
                            onPressed: address.isEmpty ? null : () => openMapsForAddress(address),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CantiereButton(
                            label: 'Dettagli',
                            kind: CantiereButtonKind.ghost,
                            compact: true,
                            onPressed: () => context.pop(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _hm(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _CantiereMap extends StatefulWidget {
  const _CantiereMap({required this.point});

  final LatLng point;

  @override
  State<_CantiereMap> createState() => _CantiereMapState();
}

class _CantiereMapState extends State<_CantiereMap> {
  bool _tileLoadFailed = false;

  @override
  Widget build(BuildContext context) {
    if (_tileLoadFailed) {
      return const _MapMessage(
        icon: LucideIcons.mapPinOff,
        message: 'Mappa non disponibile senza connessione',
      );
    }

    return FlutterMap(
      options: MapOptions(initialCenter: widget.point, initialZoom: 16, minZoom: 4, maxZoom: 19),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _osmUserAgentPackageName,
          errorTileCallback: (tile, error, stackTrace) {
            if (_tileLoadFailed || !mounted) return;
            setState(() => _tileLoadFailed = true);
          },
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: widget.point,
              width: 44,
              height: 44,
              child: Icon(LucideIcons.mapPin, color: context.colors.accentInk, size: 44),
            ),
          ],
        ),
        const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
      ],
    );
  }
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.bg2,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: context.colors.inkMuted),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(color: context.colors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.back` over the map: 32px square, sheet fill, 1px rule, 2px radius.
class _SquareBackButton extends StatelessWidget {
  const _SquareBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(color: context.colors.borderLight),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          onPressed: onTap,
          tooltip: 'Indietro',
          icon: Icon(LucideIcons.chevronLeft, size: 22, color: context.colors.ink),
        ),
      ),
    );
  }
}
