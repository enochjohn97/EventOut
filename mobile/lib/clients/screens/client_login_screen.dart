import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../providers/client_auth_provider.dart';
import '../services/client_auth_service.dart';
import '../widgets/client_signup_sheet.dart';

/// Organizer login. Deliberately email + password only — no Google, Facebook
/// or any other social provider, matching the web client portal.
class ClientLoginScreen extends StatefulWidget {
  const ClientLoginScreen({super.key});

  @override
  State<ClientLoginScreen> createState() => _ClientLoginScreenState();
}

class _ClientLoginScreenState extends State<ClientLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  bool _verificationInProgress = false;
  String? _error;

  static final _emailRule = RegExp(
    r"^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,63}$",
    caseSensitive: false,
  );

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<ClientAuthProvider>().startLogin(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      _codeCtrl.clear();
      setState(() => _submitting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_verificationInProgress) return;

    final code = _codeCtrl.text.trim();

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      if (mounted) {
        setState(() => _error = 'Enter the 6-digit code from your email.');
      }
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _verificationInProgress = true;
      _submitting = true;
      _error = null;
    });

    try {
      final ok = await context.read<ClientAuthProvider>().verifyLoginCode(code);

      if (!mounted) return;

      if (ok) {
        context.go('/client/home');
        return;
      }

      setState(() {
        _error =
            context.read<ClientAuthProvider>().error ??
            'Invalid verification code.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _verificationInProgress = false;
          _submitting = false;
        });
      }
    }
  }

  Future<void> _openSignup() async {
    final email = await showClientSignupSheet(context);
    if (!mounted || email == null) return;
    setState(() {
      _emailCtrl.text = email;
      _error = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Account created. Sign in with your password.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<ClientAuthProvider>();
    final awaitingCode = auth.awaitingCode;

    return Scaffold(
      backgroundColor: AppTheme.cream,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.sizeOf(context).height -
                      MediaQuery.paddingOf(context).vertical -
                      44,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/login');
                            }
                          },
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.storefront_outlined,
                                size: 14,
                                color: AppTheme.brandRed,
                              ),
                              SizedBox(width: 5),
                              Text(
                                'Client portal',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.brandRed,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Image.asset(
                      'assets/images/logo.png',
                      width: 58,
                      height: 58,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Welcome back',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to manage your events, tickets and payouts.',
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE9E4CE)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: _formStep(),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Text.rich(
                        TextSpan(
                          text: 'New to EventOut? ',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMuted,
                          ),
                          children: [
                            WidgetSpan(
                              child: GestureDetector(
                                onTap: _openSignup,
                                child: const Text(
                                  'Create a client account',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.brandRed,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _legalRow(),
                  ],
                ),
              ),
            ),
            if (auth.sessionExpired && !awaitingCode)
              Positioned(
                left: 24,
                right: 24,
                bottom: 16,
                child: _banner('Your session expired. Please sign in again.'),
              ),
            if (awaitingCode)
              Positioned.fill(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.56),
                  child: SafeArea(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Check your email',
                                  style: TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.textMain,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'We sent a 6-digit code to ${auth.pendingEmail ?? 'your email'}. Enter it below to continue.',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    height: 1.45,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _codeStep(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _formStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Email is required';
              if (!_emailRule.hasMatch(text)) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _signIn(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Password is required';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _submitting ? null : _forgotPassword,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Forgot password?',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.brandRed,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _signIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandRed,
                foregroundColor: Colors.white,
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeStep() {
    final auth = context.watch<ClientAuthProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofocus: true,
          maxLength: 6,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 10,
          ),
          decoration: const InputDecoration(
            counterText: '',
            hintText: '000000',
          ),
          onChanged: (value) {
            if (value.length == 6 && !_verificationInProgress && !_submitting) {
              _verifyCode();
            }
          },
          onSubmitted: (_) => _verifyCode(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.error,
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting ? null : _verifyCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brandRed,
              foregroundColor: Colors.white,
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Verify & sign in'),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: _submitting
                ? null
                : () async {
                        setState(() => _submitting = true);
                        try {
                          await auth.startLogin(
                            email: _emailCtrl.text.trim(),
                            password: _passwordCtrl.text,
                          );
                          if (!mounted) return;
                          setState(() {
                            _submitting = false;
                            _error = null;
                          });
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text('A new code has been sent.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                        } catch (e) {
                          if (!mounted) return;
                          setState(() {
                            _submitting = false;
                            _error = e.toString().replaceFirst(
                              'Exception: ',
                              '',
                            );
                          });
                        }
                  },
            child: const Text('Resend code'),
          ),
        ),
      ],
    );
  }

  Future<void> _forgotPassword() async {
    FocusScope.of(context).unfocus();
    final email = await showClientForgotPasswordDialog(
      context,
      initialEmail: _emailCtrl.text.trim(),
    );
    if (!mounted || email == null) return;
    setState(() {
      _emailCtrl.text = email;
      _passwordCtrl.clear();
      _error = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Password updated. Sign in with your new password.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _legalRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: () => context.push('/terms'),
          child: const Text(
            'Terms',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
        ),
        const Text('·', style: TextStyle(color: AppTheme.textMuted)),
        TextButton(
          onPressed: () => context.push('/privacy'),
          child: const Text(
            'Privacy Policy',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _banner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.brandRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.brandRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppTheme.brandRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.brandRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The web portal's three-step password recovery, as one dialog:
/// email → emailed 6-digit code → new password.
Future<String?> showClientForgotPasswordDialog(
  BuildContext context, {
  String initialEmail = '',
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ForgotPasswordDialog(initialEmail: initialEmail),
  );
}

class _ForgotPasswordDialog extends StatefulWidget {
  final String initialEmail;

  const _ForgotPasswordDialog({required this.initialEmail});

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _emailCtrl = TextEditingController(
    text: widget.initialEmail,
  );
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  int _step = 0;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _resetToken;

  static final _emailRule = RegExp(
    r"^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,63}$",
    caseSensitive: false,
  );

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() {
    final email = _emailCtrl.text.trim();
    return _run(() async {
      if (email.isEmpty) {
        throw Exception('Email is required');
      }
      if (!_emailRule.hasMatch(email)) {
        throw Exception('Enter a valid email address');
      }
      await ClientAuthService.requestPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _step = 1;
        _codeCtrl.clear();
      });
    });
  }

  Future<void> _verifyCode() {
    final code = _codeCtrl.text.trim();
    return _run(() async {
      if (!RegExp(r'^\d{6}$').hasMatch(code)) {
        throw Exception('Enter the 6-digit code from your email.');
      }
      final token = await ClientAuthService.verifyResetCode(
        email: _emailCtrl.text.trim(),
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _resetToken = token;
        _step = 2;
      });
    });
  }

  Future<void> _resetPassword() {
    final password = _passwordCtrl.text;
    return _run(() async {
      if (password.length < 8) {
        throw Exception('Password must be at least 8 characters long.');
      }
      if (password != _confirmCtrl.text) {
        throw Exception('Passwords do not match.');
      }
      final token = _resetToken;
      if (token == null) {
        throw Exception('Your reset session expired. Request a new code.');
      }
      await ClientAuthService.resetPassword(
        resetToken: token,
        password: password,
      );
      if (!mounted) return;
      Navigator.pop(context, _emailCtrl.text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        switch (_step) {
          1 => 'Verify the code',
          2 => 'Set a new password',
          _ => 'Forgot password?',
        },
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              switch (_step) {
                1 =>
                  'We sent a 6-digit code to ${_emailCtrl.text.trim()}. Enter it below.',
                2 => 'Choose a new password (at least 8 characters).',
                _ =>
                  'Enter your registered email address to receive a reset code.',
              },
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            if (_step == 0)
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofocus: true,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
            if (_step == 1)
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                autofocus: true,
                maxLength: 6,
                enabled: !_busy,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                ),
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '000000',
                ),
              ),
            if (_step == 2) ...[
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                autofocus: true,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'New password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscure,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.lock_reset),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _busy
              ? null
              : switch (_step) {
                  1 => _verifyCode,
                  2 => _resetPassword,
                  _ => _sendCode,
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.brandRed,
            foregroundColor: Colors.white,
          ),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  switch (_step) {
                    1 => 'Verify code',
                    2 => 'Reset password',
                    _ => 'Send code',
                  },
                ),
        ),
      ],
    );
  }
}
