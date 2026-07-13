import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_ble_alarm/core/theme/glass.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';
import 'package:smart_ble_alarm/features/account/presentation/cubit/account_cubit.dart';
import 'package:smart_ble_alarm/features/account/presentation/widgets/account_profile_editor.dart';

enum _AuthMode { signIn, create }

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;

  bool get _showAppleSignIn =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Account')),
      body: GlassBackground(
        child: SafeArea(
          child: BlocConsumer<AccountCubit, AccountState>(
            listenWhen: (previous, current) =>
                previous.message != current.message && current.message != null,
            listener: (context, state) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(content: Text(state.message!)));
            },
            builder: (context, state) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  _header(context),
                  const SizedBox(height: 24),
                  if (state.isInitializing)
                    _loadingCard(context)
                  else if (!state.firebaseReady)
                    _firebaseUnavailableCard(context, state)
                  else if (state.isSignedIn)
                    AccountProfileEditor(
                      state: state,
                      secondaryActionLabel: 'Sign Out',
                      secondaryActionIcon: Icons.logout_rounded,
                      onSecondaryAction: () =>
                          context.read<AccountCubit>().signOut(),
                    )
                  else
                    _authCard(context, state),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const WakeLogoMark(size: 58),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WakeGuard Account',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Backup and restore your setup',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _loadingCard(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      shadows: wakeCardShadow(context),
      child: const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }

  Widget _firebaseUnavailableCard(BuildContext context, AccountState state) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(22),
      shadows: wakeCardShadow(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_rounded, color: scheme.primary, size: 34),
          const SizedBox(height: 16),
          Text(
            'Firebase is not connected',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            state.message ??
                'Connect this app to your Firebase project to enable accounts.',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          WakeSecondaryButton(
            label: 'Try Again',
            icon: Icons.refresh_rounded,
            onPressed: () => context.read<AccountCubit>().start(),
          ),
        ],
      ),
    );
  }

  Widget _authCard(BuildContext context, AccountState state) {
    final scheme = Theme.of(context).colorScheme;
    final isCreate = _mode == _AuthMode.create;
    return GlassCard(
      padding: const EdgeInsets.all(22),
      shadows: wakeCardShadow(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WakeAuthProviderButton(
            label: state.isBusy ? 'Please Wait...' : 'Continue with Google',
            mark: 'G',
            onPressed: state.isBusy
                ? null
                : () => context.read<AccountCubit>().signInWithGoogle(),
          ),
          if (_showAppleSignIn) ...[
            const SizedBox(height: 10),
            WakeAuthProviderButton(
              label: state.isBusy ? 'Please Wait...' : 'Continue with Apple',
              icon: Icons.apple,
              onPressed: state.isBusy
                  ? null
                  : () => context.read<AccountCubit>().signInWithApple(),
            ),
          ],
          const SizedBox(height: 18),
          _AuthDivider(label: 'or use email'),
          const SizedBox(height: 18),
          SegmentedButton<_AuthMode>(
            segments: const [
              ButtonSegment(value: _AuthMode.signIn, label: Text('Sign In')),
              ButtonSegment(
                value: _AuthMode.create,
                label: Text('Create Account'),
              ),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: scheme.primary,
              selectedForegroundColor: scheme.onPrimary,
              side: BorderSide(color: GlassTheme.of(context).stroke),
            ),
            onSelectionChanged: state.isBusy
                ? null
                : (selection) => setState(() => _mode = selection.first),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_rounded),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordController,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: isCreate
                ? const [AutofillHints.newPassword]
                : const [AutofillHints.password],
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_rounded),
            ),
            onSubmitted: (_) => _submit(context),
          ),
          const SizedBox(height: 20),
          WakePrimaryButton(
            label: state.isBusy
                ? 'Please Wait...'
                : (isCreate ? 'Create Account' : 'Sign In'),
            icon: isCreate ? Icons.person_add_rounded : Icons.login_rounded,
            onPressed: state.isBusy ? null : () => _submit(context),
          ),
          if (!isCreate) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: state.isBusy
                  ? null
                  : () => context.read<AccountCubit>().sendPasswordReset(
                      _emailController.text,
                    ),
              child: const Text('Reset password'),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'WakeGuard still works locally if you skip sign-in.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  void _submit(BuildContext context) {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Enter your email and password.')),
        );
      return;
    }

    final cubit = context.read<AccountCubit>();
    if (_mode == _AuthMode.create) {
      cubit.createAccount(email: email, password: password);
    } else {
      cubit.signIn(email: email, password: password);
    }
  }
}

class _AuthDivider extends StatelessWidget {
  final String label;

  const _AuthDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineColor = GlassTheme.of(context).stroke;
    return Row(
      children: [
        Expanded(child: Divider(color: lineColor, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(child: Divider(color: lineColor, height: 1)),
      ],
    );
  }
}
