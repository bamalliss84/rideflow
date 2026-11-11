import 'package:flutter/material.dart';
import '../../core/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../shared/widgets.dart' show errorMessage;

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController(text: currentSettings.region.phoneCode);
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  Object? _error;

  static final _phonePattern = RegExp(r'^\+[1-9]\d{7,14}$');
  String get _normalizedPhone => _phone.text.replaceAll(RegExp(r'[\s-]'), '');

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
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

  Future<void> _sendCode() async {
    if (!_phonePattern.hasMatch(_normalizedPhone)) {
      setState(() => _error = AppLocalizations.of(context).invalidPhone);
      return;
    }
    await _run(() async {
      await ref.read(riderApiProvider).requestOtp(_normalizedPhone);
      setState(() => _codeSent = true);
    });
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 4) return;
    await _run(() => ref.read(authProvider.notifier).signIn(_normalizedPhone, _code.text.trim(), fullName: _name.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(22, 40, 22, 22), children: [
          const Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: RfLogo(size: 30)),
          ),
          const SizedBox(height: 56),
          if (!_codeSent) ...[
            Text(t.signInHeadline, style: RfType.h1),
            const SizedBox(height: 8),
            Text(t.signInSubtitle, style: RfType.body.copyWith(color: RfColors.textMuted, height: 1.6)),
            const SizedBox(height: 28),
            TextField(
              key: const Key('phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[+\d\s-]'))],
              decoration: InputDecoration(labelText: t.phoneLabel),
              onSubmitted: (_) => _sendCode(),
            ),
            const SizedBox(height: 24),
            RfButton(key: const Key('sendCode'), label: t.sendCode, large: true, loading: _busy, onPressed: _sendCode),
          ] else ...[
            Text(t.codeTitle, style: RfType.h1),
            const SizedBox(height: 8),
            Text(t.codeSentTo(_normalizedPhone), style: RfType.body.copyWith(color: RfColors.textMuted, height: 1.6)),
            const SizedBox(height: 24),
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
            ),
            const SizedBox(height: 16),
            TextField(key: const Key('name'), controller: _name, maxLength: 60, decoration: InputDecoration(labelText: t.firstNameOnce, counterText: '')),
            const SizedBox(height: 24),
            RfButton(key: const Key('verify'), label: t.confirm, large: true, loading: _busy, onPressed: _verify),
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
        ]),
      ),
    );
  }
}
