import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/icons/app_lucide_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inline_alert.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../data/access_requests/access_request_api_client.dart';

Future<void> showAccessRequestSheet(BuildContext context, {String initialEmail = ''}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _AccessRequestSheet(initialEmail: initialEmail),
  );
}

class _AccessRequestSheet extends ConsumerStatefulWidget {
  const _AccessRequestSheet({required this.initialEmail});

  final String initialEmail;

  @override
  ConsumerState<_AccessRequestSheet> createState() => _AccessRequestSheetState();
}

class _AccessRequestSheetState extends ConsumerState<_AccessRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl;
  final _nameCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail.trim());
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _companyCtrl.dispose();
    _phoneCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Inserisci la tua email.';
    if (email.length > kAccessRequestMaxEmailLength || !_emailShape.hasMatch(email)) {
      return 'Inserisci un indirizzo email valido.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref
          .read(accessRequestApiClientProvider)
          .submit(
            email: _emailCtrl.text,
            name: _nameCtrl.text,
            company: _companyCtrl.text,
            phone: _phoneCtrl.text,
            message: _messageCtrl.text,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = humanErrorMessage(error, azione: 'inviare la richiesta', workIsSafe: false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              AppSpacing.sm,
              AppSpacing.pagePadding,
              AppSpacing.md,
            ),
            children: _sent ? _success(context) : _form(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _form(BuildContext context) {
    return [
      Row(
        children: [
          Expanded(child: Text('Richiedi accesso', style: AppTextStyles.headlineMedium)),
          HeaderIconBtn(
            icon: LucideIcons.x,
            label: 'Chiudi',
            onTap: _busy ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Non hai ancora un account? Lasciaci i tuoi dati e ti contatteremo per attivarlo.',
        style: AppTextStyles.bodyMedium.copyWith(color: context.colors.inkFaint),
      ),
      const SizedBox(height: AppSpacing.lg),
      Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              key: const ValueKey('access-request-email'),
              controller: _emailCtrl,
              label: 'Email *',
              hint: 'nome@azienda.it',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              maxLength: kAccessRequestMaxEmailLength,
              counterText: '',
              validator: _validateEmail,
            ),
            const SizedBox(height: AppSpacing.base),
            AppTextField(
              key: const ValueKey('access-request-name'),
              controller: _nameCtrl,
              label: 'Nome (facoltativo)',
              textInputAction: TextInputAction.next,
              maxLength: kAccessRequestMaxNameLength,
              counterText: '',
            ),
            const SizedBox(height: AppSpacing.base),
            AppTextField(
              key: const ValueKey('access-request-company'),
              controller: _companyCtrl,
              label: 'Azienda (facoltativo)',
              textInputAction: TextInputAction.next,
              maxLength: kAccessRequestMaxCompanyLength,
              counterText: '',
            ),
            const SizedBox(height: AppSpacing.base),
            AppTextField(
              key: const ValueKey('access-request-phone'),
              controller: _phoneCtrl,
              label: 'Telefono (facoltativo)',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              maxLength: kAccessRequestMaxPhoneLength,
              counterText: '',
            ),
            const SizedBox(height: AppSpacing.base),
            AppTextField.multiline(
              key: const ValueKey('access-request-message'),
              controller: _messageCtrl,
              label: 'Messaggio (facoltativo)',
              hint: 'Dicci come possiamo aiutarti.',
              maxLength: kAccessRequestMaxMessageLength,
              maxLines: 4,
            ),
          ],
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: AppSpacing.base),
        InlineAlert(message: _error!, icon: LucideIcons.alertCircle),
      ],
      const SizedBox(height: AppSpacing.lg),
      AppButton(
        key: const ValueKey('access-request-submit'),
        label: 'Invia richiesta',
        isLoading: _busy,
        onPressed: _submit,
      ),
      const SizedBox(height: AppSpacing.sm),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Annulla'),
      ),
    ];
  }

  List<Widget> _success(BuildContext context) {
    return [
      Align(
        alignment: Alignment.centerRight,
        child: HeaderIconBtn(
          icon: LucideIcons.x,
          label: 'Chiudi',
          onTap: () => Navigator.of(context).pop(),
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      Center(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: context.colors.green.withAlpha(20),
            shape: BoxShape.circle,
          ),
          child: Icon(LucideIcons.checkCircle2, color: context.colors.green, size: 28),
        ),
      ),
      const SizedBox(height: AppSpacing.base),
      Text(
        'Richiesta inviata. Ti contatteremo.',
        textAlign: TextAlign.center,
        style: AppTextStyles.titleMedium.copyWith(color: context.colors.ink),
      ),
      const SizedBox(height: AppSpacing.xl),
      AppButton(label: 'Chiudi', onPressed: () => Navigator.of(context).pop()),
    ];
  }
}
