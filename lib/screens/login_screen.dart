import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../agreements/user_agreement.dart';
import '../agreements/privacy_policy.dart';
import '../agreements/network_usage_agreement.dart';
import '../providers/auth_provider.dart';
import '../l10n/app_localizations.dart';
import '../services/agreement_service.dart';
import '../services/auth_service.dart';
import '../services/no_email_account_store.dart';
import '../widgets/email_input_field.dart';
import 'forgot_password_screen.dart';

/// 登录/注册页面 — 可独立使用，也可嵌入引导页
class LoginScreen extends ConsumerStatefulWidget {
  /// 嵌入模式下不显示 AppBar 和背景
  final bool embedded;
  /// 登录/注册成功后的回调
  final VoidCallback? onSuccess;

  const LoginScreen({super.key, this.embedded = false, this.onSuccess});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 登录表单
  final _loginUsernameCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool _loginObscure = true;

  // 注册表单
  final _regUsernameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regCodeCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();
  final _regConfirmCtrl = TextEditingController();
  final _regNicknameCtrl = TextEditingController();
  bool _regObscure = true;
  bool _regConfirmObscure = true;
  bool _sendingCode = false;
  int _codeCountdown = 0;

  bool _hasAgreedRegister = false;
  bool _hasAgreedLogin = false;
  bool _handledSuccess = false;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _regEmailCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAgreementStatus();
  }

  Future<void> _loadAgreementStatus() async {
    final all = await AgreementService.instance.allAgreed();
    if (all && mounted) {
      setState(() {
        _hasAgreedRegister = true;
        _hasAgreedLogin = true;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginUsernameCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _regUsernameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regCodeCtrl.dispose();
    _regPasswordCtrl.dispose();
    _regConfirmCtrl.dispose();
    _regNicknameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authProvider);

    // 监听登录成功
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.isLoggedIn &&
          !(prev?.isLoggedIn ?? false) &&
          !_handledSuccess) {
        _handledSuccess = true;
        widget.onSuccess?.call();
        if (!widget.embedded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context, true);
            }
          });
        }
      }
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!), backgroundColor: scheme.error),
        );
      }
    });

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.embedded) const SizedBox(height: 40),
        Text(
          l10n.get('onboardingAccount'),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: scheme.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.get('onboardingAccountDesc'),
          style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 24),

        // Tab 切换
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.get('login')),
            Tab(text: l10n.get('register')),
          ],
          onTap: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),

        // 表单
        _tabController.index == 0
            ? _buildLoginForm(l10n, scheme, auth)
            : _buildRegisterForm(l10n, scheme, auth),
      ],
    );

    if (widget.embedded) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: content,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('onboardingAccount'))),
      body: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: content,
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm(AppLocalizations l10n, ColorScheme scheme, AuthState auth) {
    return Column(
      children: [
        TextField(
          controller: _loginUsernameCtrl,
          decoration: InputDecoration(
            labelText: l10n.get('usernameOrEmail'),
            prefixIcon: const Icon(Icons.person_outline),
            border: const OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _loginPasswordCtrl,
          obscureText: _loginObscure,
          decoration: InputDecoration(
            labelText: l10n.get('password'),
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_loginObscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _loginObscure = !_loginObscure),
            ),
          ),
          onSubmitted: (_) => _doLogin(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () async {
              final username = _loginUsernameCtrl.text.trim();
              if (username.isNotEmpty &&
                  await NoEmailAccountStore.isNoEmail(username)) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.get('noEmailCannotRecover'))),
                );
                return;
              }
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
              );
            },
            child: Text(
              l10n.get('forgotPassword'),
              style: TextStyle(fontSize: 13, color: scheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: auth.isLoading ? null : _doLogin,
            child: auth.isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.get('login')),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildRegisterForm(AppLocalizations l10n, ColorScheme scheme, AuthState auth) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _regUsernameCtrl,
            decoration: InputDecoration(
              labelText: l10n.get('username'),
              prefixIcon: const Icon(Icons.person_outline),
              border: const OutlineInputBorder(),
              helperText: l10n.get('usernameHint'),
            ),
            validator: (v) {
              if (v == null || v.trim().length < 3) return l10n.get('usernameTooShort');
              if (v.trim().length > 32) return l10n.get('usernameTooLong');
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          // 邮箱输入：前缀 + 下拉后缀 + 自定义（选填，不绑定无法找回账号）
          EmailInputField(
            controller: _regEmailCtrl,
            labelText: '${l10n.get('email')}（${l10n.get('emailOptional')}）',
            helperText: l10n.get('emailHint'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: scheme.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.get('noEmailWarning'),
                  style: TextStyle(fontSize: 12, color: scheme.tertiary, height: 1.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 验证码 + 发送按钮（仅绑定邮箱时需要）
          if (_regEmailCtrl.text.trim().isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _regCodeCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.get('emailCode'),
                      prefixIcon: const Icon(Icons.verified_user_outlined),
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 12,
                    validator: (v) {
                      if (_regEmailCtrl.text.trim().isEmpty) return null;
                      if (v == null || v.length < 6) return l10n.get('invalidCode');
                      return null;
                    },
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  child: FilledButton.tonal(
                    onPressed: (_sendingCode || _codeCountdown > 0) ? null : _sendRegCode,
                    child: _sendingCode
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_codeCountdown > 0 ? '${_codeCountdown}s' : l10n.get('sendCode')),
                  ),
                ),
              ],
            ),
          if (_regEmailCtrl.text.trim().isNotEmpty) const SizedBox(height: 16),
          TextFormField(
            controller: _regNicknameCtrl,
            decoration: InputDecoration(
              labelText: l10n.get('nickname'),
              prefixIcon: const Icon(Icons.face),
              border: const OutlineInputBorder(),
              helperText: l10n.get('nicknameHint'),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _regPasswordCtrl,
            obscureText: _regObscure,
            decoration: InputDecoration(
              labelText: l10n.get('password'),
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              helperText: l10n.get('passwordHint'),
              suffixIcon: IconButton(
                icon: Icon(_regObscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _regObscure = !_regObscure),
              ),
            ),
            validator: (v) {
              if (v == null || v.length < 8) return l10n.get('passwordTooShort');
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _regConfirmCtrl,
            obscureText: _regConfirmObscure,
            decoration: InputDecoration(
              labelText: l10n.get('confirmPassword'),
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_regConfirmObscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _regConfirmObscure = !_regConfirmObscure),
              ),
            ),
            validator: (v) {
              if (v != _regPasswordCtrl.text) return l10n.get('passwordMismatch');
              return null;
            },
            onFieldSubmitted: (_) => _doRegister(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _hasAgreedRegister,
                onChanged: (v) => _onRegisterAgreeChanged(v ?? false),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _onRegisterAgreeChanged(!_hasAgreedRegister),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      children: [
                        TextSpan(text: l10n.get('iHaveReadAndAgree')),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => _showAgreementViewer(context, UserAgreement.title, UserAgreement.content),
                            child: Text(
                              l10n.get('userAgreement'),
                              style: TextStyle(fontSize: 13, color: scheme.primary, decoration: TextDecoration.underline),
                            ),
                          ),
                        ),
                        TextSpan(text: l10n.get('agreementSeparator')),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => _showAgreementViewer(context, PrivacyPolicy.title, PrivacyPolicy.content),
                            child: Text(
                              l10n.get('privacyPolicy'),
                              style: TextStyle(fontSize: 13, color: scheme.primary, decoration: TextDecoration.underline),
                            ),
                          ),
                        ),
                        TextSpan(text: l10n.get('agreementAnd')),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => _showAgreementViewer(context, NetworkUsageAgreement.title, NetworkUsageAgreement.content),
                            child: Text(
                              l10n.get('networkUsageAgreement'),
                              style: TextStyle(fontSize: 13, color: scheme.primary, decoration: TextDecoration.underline),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: auth.isLoading ? null : _doRegister,
              child: auth.isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.get('register')),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _doLogin() {
    final u = _loginUsernameCtrl.text.trim();
    final p = _loginPasswordCtrl.text;
    if (u.isEmpty || p.isEmpty) return;
    if (!_hasAgreedLogin) {
      _showLoginAgreementDialog();
      return;
    }
    ref.read(authProvider.notifier).login(username: u, password: p);
  }

  /// 注册表单勾选/取消勾选三份协议
  Future<void> _onRegisterAgreeChanged(bool agreed) async {
    setState(() => _hasAgreedRegister = agreed);
    if (agreed) {
      await AgreementService.instance.markAgreed('user_agreement', UserAgreement.version);
      await AgreementService.instance.markAgreed('privacy_policy', PrivacyPolicy.version);
      await AgreementService.instance.markAgreed('network_usage', NetworkUsageAgreement.version);
      _hasAgreedLogin = true;
    }
  }

  void _doRegister() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_hasAgreedRegister) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.get('pleaseAgreeFirst')), backgroundColor: Theme.of(context).colorScheme.error),
      );
      return;
    }
    final email = _regEmailCtrl.text.trim();
    if (email.isEmpty) {
      // 不绑定邮箱注册（无法找回账号，界面已有警告提示）
      ref.read(authProvider.notifier).register(
        username: _regUsernameCtrl.text.trim(),
        email: '',
        password: _regPasswordCtrl.text,
        nickname: _regNicknameCtrl.text.trim(),
      );
      return;
    }
    ref.read(authProvider.notifier).registerWithCode(
      username: _regUsernameCtrl.text.trim(),
      email: email,
      password: _regPasswordCtrl.text,
      code: _regCodeCtrl.text.trim(),
      nickname: _regNicknameCtrl.text.trim(),
    );
  }

  Future<void> _sendRegCode() async {
    final email = _regEmailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).get('invalidEmail'))),
      );
      return;
    }
    setState(() => _sendingCode = true);
    try {
      await AuthService().sendCode(email, 'register');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).get('codeSent'))),
      );
      _startCodeCountdown();
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).get('networkError'))),
      );
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  void _startCodeCountdown() {
    setState(() => _codeCountdown = 60);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _codeCountdown--);
      return _codeCountdown > 0;
    });
  }

  /// 以全屏弹窗展示完整的协议/政策内容
  void _showAgreementViewer(BuildContext ctx, String title, String content) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              content,
              style: TextStyle(fontSize: 14, height: 1.6, color: Theme.of(ctx).colorScheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  /// 登录时弹出协议确认对话框
  void _showLoginAgreementDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.get('agreementConfirm')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.get('agreementConfirmDesc')),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _showAgreementViewer(context, UserAgreement.title, UserAgreement.content),
              child: Text(
                l10n.get('userAgreement'),
                style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showAgreementViewer(context, PrivacyPolicy.title, PrivacyPolicy.content),
              child: Text(
                l10n.get('privacyPolicy'),
                style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showAgreementViewer(context, NetworkUsageAgreement.title, NetworkUsageAgreement.content),
              child: Text(
                l10n.get('networkUsageAgreement'),
                style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              await AgreementService.instance.markAgreed('user_agreement', UserAgreement.version);
              await AgreementService.instance.markAgreed('privacy_policy', PrivacyPolicy.version);
              await AgreementService.instance.markAgreed('network_usage', NetworkUsageAgreement.version);
              if (!mounted) return;
              Navigator.pop(ctx); // ignore: use_build_context_synchronously
              setState(() {
                _hasAgreedLogin = true;
                _hasAgreedRegister = true;
              });
              _doLogin();
            },
            child: Text(l10n.get('agreeAndLogin')),
          ),
        ],
      ),
    );
  }
}
