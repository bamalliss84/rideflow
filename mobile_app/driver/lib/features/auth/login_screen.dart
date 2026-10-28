import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/widgets.dart' show errorMessage;

final _appContextProvider = FutureProvider.autoDispose((ref) => ref.watch(driverApiProvider).appContext());

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  Object? _error;

  static final _phonePattern = RegExp(r'^\+[1-9]\d{7,14}$');

  String get _normalizedPhone => _phone.text.replaceAll(RegExp(r'[\s-]'), '');

  Future<void> _sendCode() async {
    if (!_phonePattern.hasMatch(_normalizedPhone)) {
      setState(() => _error = AppLocalizations.of(context).invalidPhone);
      return;
    }
    await _run(() async {
      await ref.read(driverApiProvider).requestOtp(_normalizedPhone);
      setState(() => _codeSent = true);
    });
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 4) return;
    await _run(() => ref.read(authProvider.notifier).signIn(_normalizedPhone, _code.text.trim()));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final operator = ref.watch(_appContextProvider).valueOrNull?['tenant_name'] as String?;
    return Scaffold(
      backgroundColor: RfColors.surface,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () {
                final current = ref.read(localeProvider);
                ref.read(localeProvider.notifier).state = Locale(current.languageCode == 'ar' ? 'en' : 'ar');
              },
              icon: const Icon(Icons.translate),
              label: Text(t.switchLanguage),
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: RfColors.ink, borderRadius: BorderRadius.circular(RfRadius.lg), boxShadow: RfShadow.card),
            child: const Icon(Icons.local_taxi_rounded, color: RfColors.teal, size: 34),
          ),
          ),
          const SizedBox(height: 20),
          Text(t.signInTitle, style: RfType.display),
          const SizedBox(height: 6),
          Text(t.signInSubtitle, style: RfType.body.copyWith(color: RfColors.textMuted)),
          if (operator != null) ...[
            const SizedBox(height: 12),
            Align(alignment: AlignmentDirectional.centerStart, child: StatusPill(t.operatorLabel(operator), tone: Tone.info, icon: Icons.apartment_rounded)),
          ],
          const SizedBox(height: 28),
          if (!_codeSent) ...[
            TextField(
              key: const Key('phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[+\d\s-]'))],
              decoration: InputDecoration(labelText: t.phoneLabel, hintText: '+967…', helperText: t.phoneHint, prefixIcon: const Icon(Icons.phone_iphone)),
              onSubmitted: (_) => _sendCode(),
            ),
            const SizedBox(height: 20),
            RfButton(key: const Key('sendCode'), label: t.sendCode, large: true, loading: _busy, onPressed: _sendCode),
          ] else ...[
            Text(t.codeSentTo(_normalizedPhone), style: RfType.body.copyWith(color: RfColors.textMuted)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('code'),
              controller: _code,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              maxLength: 8,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: RfType.h1.copyWith(letterSpacing: 8),
              decoration: InputDecoration(labelText: t.codeLabel, counterText: ''),
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 16),
            RfButton(key: const Key('verify'), label: t.verify, large: true, loading: _busy, onPressed: _verify),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _codeSent = false;
                        _code.clear();
                        _error = null;
                      }),
              child: Text(t.changeNumber),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Banner2(text: _error is String ? _error as String : errorMessage(context, _error!), tone: Tone.danger, icon: Icons.error_outline_rounded),
          ],
          if (kDebugMode) ...[
            const SizedBox(height: 32),
            Text(t.serverLabel('${AppConfig.environmentLabel} · ${AppConfig.apiBaseUrl}'),
                textAlign: TextAlign.center, style: RfType.caption.copyWith(fontSize: 11)),
          ],
        ]),
      ),
    );
  }
}
