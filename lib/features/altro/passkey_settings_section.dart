// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/security/passkey_support.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/widgets.dart';
import '../../data/auth/passkey_enroller.dart';
import '../../domain/auth/auth_failure.dart';

const _sectionTitle = 'Accesso con passkey';
const _warning =
    'La passkey è protetta dal blocco schermo di questo dispositivo. '
    'Attivala solo su un dispositivo personale.';
const _defaultPasskeyName = 'TaskTap su questo dispositivo';
const _emptyListCopy = 'Nessuna passkey attiva su questo dispositivo.';

/// The signed-in user's passkeys, as a settings card.
///
/// A failed [PasskeyEnroller.list] is rendered as a failure with a retry, never
/// collapsed into the empty state: "no passkeys" is a real answer and must not be
/// indistinguishable from "the list could not be fetched".
final passkeyListProvider =
    FutureProvider.autoDispose<({List<PasskeySummary> items, AuthFailure? failure})>(
      (ref) => ref.watch(passkeyEnrollerProvider).list(),
    );

class PasskeySettingsSection extends ConsumerWidget {
  const PasskeySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported = ref.watch(passkeySupportedProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const RowIconTile(icon: LucideIcons.fingerprint, size: 34, iconSize: 17),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _sectionTitle,
                    style: AppTextStyles.titleMedium.copyWith(color: context.colors.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _warning,
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 11,
                height: 1.4,
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            supported.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, _) => const _UnsupportedPasskeys(),
              data: (isSupported) =>
                  isSupported ? const _PasskeyListBody() : const _UnsupportedPasskeys(),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnsupportedPasskeys extends StatelessWidget {
  const _UnsupportedPasskeys();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineAlert(
          message: authFailureMessage(const PasskeyUnavailable()),
          icon: LucideIcons.alertCircle,
        ),
        const SizedBox(height: AppSpacing.md),
        const AppButton(label: 'Attiva accesso con passkey', onPressed: null),
      ],
    );
  }
}

class _PasskeyListBody extends ConsumerStatefulWidget {
  const _PasskeyListBody();

  @override
  ConsumerState<_PasskeyListBody> createState() => _PasskeyListBodyState();
}

class _PasskeyListBodyState extends ConsumerState<_PasskeyListBody> {
  bool _busy = false;
  AuthFailure? _actionFailure;

  Future<void> _enrol() async {
    setState(() {
      _busy = true;
      _actionFailure = null;
    });

    final result = await ref.read(passkeyEnrollerProvider).enrol(name: _defaultPasskeyName);
    if (!mounted) return;

    if (!result.ok) {
      // A dismissed platform sheet is not a failure: it reports `failure: null`
      // and deserves no error banner.
      setState(() {
        _busy = false;
        _actionFailure = result.failure;
      });
      return;
    }

    // Refresh before the toast, so the list the technician sees already contains
    // the passkey the toast is claiming exists. The enrolment itself succeeded,
    // so a failed read-back must not reopen the action as a failure of enrolment
    // — but it must not claim success either. The provider's error state renders
    // the retry branch; this only makes sure `_busy` cannot stay stuck and that
    // the error never escapes the button handler.
    ref.invalidate(passkeyListProvider);
    var refreshed = false;
    try {
      await ref.read(passkeyListProvider.future);
      refreshed = true;
    } catch (error) {
      debugPrint('Passkey list refresh failed after enrolment: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    if (refreshed) {
      showAppToast(context, message: 'Passkey attivata.', tone: ToastTone.success);
    }
  }

  Future<void> _remove(PasskeySummary passkey) async {
    final confirmed = await confirmDeleteDialog(
      context,
      title: 'Rimuovi la passkey?',
      message:
          'La passkey verrà rimossa dal tuo account. '
          'Non sarà più possibile usarla per accedere.',
      confirmLabel: 'Rimuovi',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _actionFailure = null;
    });

    final result = await ref.read(passkeyEnrollerProvider).remove(passkey.id);
    if (!mounted) return;

    if (result.ok) {
      ref.invalidate(passkeyListProvider);
      setState(() => _busy = false);
      return;
    }

    setState(() {
      _busy = false;
      _actionFailure = result.failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(passkeyListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_actionFailure case final failure?) ...[
          InlineAlert(message: authFailureMessage(failure), icon: LucideIcons.alertCircle),
          const SizedBox(height: AppSpacing.md),
        ],
        listAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, _) => _ListFailure(
            message: 'Impossibile caricare le passkey. Riprova.',
            onRetry: () => ref.invalidate(passkeyListProvider),
          ),
          data: (result) {
            final failure = result.failure;
            if (failure != null) {
              return _ListFailure(
                message: authFailureMessage(failure),
                onRetry: () => ref.invalidate(passkeyListProvider),
              );
            }
            if (result.items.isEmpty) {
              return Text(
                _emptyListCopy,
                style: TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 12,
                  height: 1.4,
                  color: context.colors.inkMuted,
                ),
              );
            }
            return Column(
              children: [
                for (final passkey in result.items)
                  _PasskeyRow(passkey: passkey, onRemove: _busy ? null : () => _remove(passkey)),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.base),
        AppButton(
          label: 'Attiva accesso con passkey',
          isLoading: _busy,
          onPressed: _busy ? null : _enrol,
        ),
      ],
    );
  }
}

class _ListFailure extends StatelessWidget {
  const _ListFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineAlert(message: message, icon: LucideIcons.alertCircle),
        const SizedBox(height: AppSpacing.sm),
        AppButton.secondary(label: 'Riprova', size: AppButtonSize.sm, onPressed: onRetry),
      ],
    );
  }
}

class _PasskeyRow extends StatelessWidget {
  const _PasskeyRow({required this.passkey, required this.onRemove});

  final PasskeySummary passkey;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(LucideIcons.fingerprint, size: 16, color: context.colors.inkMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              passkey.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Archivo', fontSize: 12, color: context.colors.ink),
            ),
          ),
          AppButton.ghost(label: 'Rimuovi passkey', size: AppButtonSize.sm, onPressed: onRemove),
        ],
      ),
    );
  }
}
