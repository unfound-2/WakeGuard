import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_ble_alarm/core/observability/app_analytics.dart';
import 'package:smart_ble_alarm/core/theme/glass.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';
import 'package:smart_ble_alarm/features/account/presentation/cubit/account_cubit.dart';
import 'package:smart_ble_alarm/features/account/presentation/widgets/account_profile_editor.dart';

enum _OnboardingAuthMode { signIn, create }

class OnboardingScreen extends StatefulWidget {
  final SharedPreferences prefs;

  /// Turns THIS device into a standby Dedicated Clock (Beta). Wired from
  /// `main.dart`; drives the onboarding "Set up this device as the clock" box on
  /// the final page. When null the box is hidden.
  final VoidCallback? onSetupDedicatedClock;

  /// Called once onboarding is complete or skipped. The app router owns the
  /// next screen so setup callbacks remain connected.
  final Future<void> Function()? onComplete;

  const OnboardingScreen({
    super.key,
    required this.prefs,
    this.onSetupDedicatedClock,
    this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _hasSeenOnboardingKey = 'hasSeenOnboarding';

  final PageController _pageController = PageController();
  int _selectedPage = 0;
  bool _isPreparing = false;

  final List<_OnboardingPage> _pages = const [
    _OnboardingPage(
      analyticsName: 'welcome',
      eyebrow: 'WakeGuard',
      title: 'Built for mornings that normal alarms do not solve.',
      body:
          'WakeGuard was made for people who sleep through alarms, dismiss them on autopilot, or wake with heavy sleep inertia. That can happen with narcolepsy, demanding schedules, medication routines, and other hard mornings.',
      icon: Icons.wb_sunny_rounded,
      bullets: [
        'Designed for difficult wake-ups',
        'Clear protection status',
        'Not a medical device',
      ],
    ),
    _OnboardingPage(
      analyticsName: 'wake_challenge',
      eyebrow: 'Wake Challenge',
      title: 'The alarm asks for proof you are moving.',
      body:
          'Instead of one easy bedside swipe, WakeGuard can require a QR code or photo check tied to your routine, like the sink, medication, coffee maker, or front door.',
      icon: Icons.center_focus_strong_rounded,
      bullets: [
        'Per-alarm challenge settings',
        'Backup code when needed',
        'Built around your morning path',
      ],
    ),
    _OnboardingPage(
      analyticsName: 'sync',
      eyebrow: 'Protection',
      title: 'Know what is ready before you sleep.',
      body:
          'WakeGuard tracks the pieces that matter: alarm set, challenge chosen, phone backup on, cloud backup saved, and clock sync when a WakeGuard clock is paired.',
      icon: Icons.cloud_done_rounded,
      bullets: [
        'Firebase alarm backups',
        'Phone fallback notifications',
        'Status language you can trust',
      ],
    ),
    _OnboardingPage(
      analyticsName: 'setup',
      eyebrow: 'Setup',
      title: 'Start with this phone. Add the clock when ready.',
      body:
          'You can use WakeGuard locally, sign in for restore, pair a physical clock, or turn a spare phone into a dedicated bedside clock.',
      icon: Icons.bluetooth_connected_rounded,
      bullets: [
        'Pair over Bluetooth',
        'Use this phone as a dedicated clock',
        'Skip setup and come back later',
      ],
    ),
  ];

  int get _profilePageIndex => _pages.length;
  int get _dedicatedClockPageIndex => _pages.length - 1;
  int get _pageCount => _pages.length + 1;
  bool get _isLastPage => _selectedPage == _profilePageIndex;
  bool get _isProfileLeadIn => _selectedPage == _profilePageIndex - 1;

  @override
  void initState() {
    super.initState();
    unawaited(_trackPage(0));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_isLastPage) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    setState(() => _isPreparing = true);
    await _finishOnboarding();

    if (!mounted) return;
  }

  Future<void> _skip() async {
    setState(() => _isPreparing = true);
    unawaited(
      AppAnalytics.instance.onboardingSkipped(
        index: _selectedPage,
        step: _stepName(_selectedPage),
      ),
    );
    await _finishOnboarding();

    if (!mounted) return;
  }

  /// The onboarding "Set up this device as the clock" box: mark onboarding seen
  /// so it doesn't reappear if the user later exits the mode, then hand off to
  /// `main.dart`, which persists Dedicated Clock mode and swaps `home:` to the
  /// full-screen clock face (this widget is torn down by that rebuild).
  Future<void> _setupDedicatedClock() async {
    setState(() => _isPreparing = true);
    unawaited(
      AppAnalytics.instance.logEvent(
        'onboarding_dedicated_clock_selected',
        parameters: {'step': _stepName(_selectedPage)},
      ),
    );
    await widget.prefs.setBool(_hasSeenOnboardingKey, true);

    if (!mounted) return;
    widget.onSetupDedicatedClock?.call();
  }

  Future<void> _finishOnboarding() async {
    unawaited(AppAnalytics.instance.onboardingCompleted());
    final onComplete = widget.onComplete;
    if (onComplete != null) {
      await onComplete();
      return;
    }
    await widget.prefs.setBool(_hasSeenOnboardingKey, true);
  }

  Future<void> _trackPage(int index) {
    return AppAnalytics.instance.onboardingStepViewed(
      index: index,
      step: _stepName(index),
    );
  }

  String _stepName(int index) {
    if (index == _profilePageIndex) return 'profile';
    return _pages[index].analyticsName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                    child: _OnboardingHeader(
                      currentPage: _selectedPage + 1,
                      pageCount: _pageCount,
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _pageCount,
                      onPageChanged: (index) {
                        setState(() => _selectedPage = index);
                        unawaited(_trackPage(index));
                      },
                      itemBuilder: (context, index) {
                        if (index == _profilePageIndex) {
                          return _OnboardingProfileView(onContinue: _continue);
                        }
                        return _OnboardingPageView(page: _pages[index]);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    child: _OnboardingFooter(
                      selectedPage: _selectedPage,
                      pageCount: _pageCount,
                      isLastPage: _isLastPage,
                      isProfileLeadIn: _isProfileLeadIn,
                      isProfilePage: _selectedPage == _profilePageIndex,
                      onSkip: _skip,
                      onContinue: _continue,
                      onSetupDedicatedClock:
                          widget.onSetupDedicatedClock == null ||
                              _selectedPage != _dedicatedClockPageIndex
                          ? null
                          : _setupDedicatedClock,
                    ),
                  ),
                ],
              ),
              if (_isPreparing) const _PreparingOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final String analyticsName;
  final String eyebrow;
  final String title;
  final String body;
  final IconData icon;
  final List<String> bullets;

  const _OnboardingPage({
    required this.analyticsName,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.icon,
    required this.bullets,
  });
}

class _OnboardingHeader extends StatelessWidget {
  final int currentPage;
  final int pageCount;

  const _OnboardingHeader({required this.currentPage, required this.pageCount});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = (currentPage / pageCount).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 7,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: scheme.onSurface.withValues(alpha: 0.10)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: ColoredBox(color: scheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: GlassTheme.of(context).stroke),
          ),
          child: Text(
            '$currentPage/$pageCount',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  final _OnboardingPage page;

  const _OnboardingPageView({required this.page});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final compactHeight = MediaQuery.sizeOf(context).height < 700;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, compactHeight ? 8 : 18, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: _WakeSetupPreview(page: page, compact: compactHeight),
          ),
          SizedBox(height: compactHeight ? 22 : 30),
          Text(
            page.eyebrow,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            page.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            page.body,
            style: TextStyle(
              fontSize: 16,
              height: 1.45,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
          _OnboardingDetailCard(page: page),
        ],
      ),
    );
  }
}

class _WakeSetupPreview extends StatelessWidget {
  final _OnboardingPage page;
  final bool compact;

  const _WakeSetupPreview({required this.page, required this.compact});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassTheme.of(context);
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: compact ? 176 : 214),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: glass.stroke),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerHighest.withValues(alpha: 0.62),
            scheme.surface.withValues(alpha: 0.18),
          ],
        ),
        boxShadow: wakeCardShadow(context),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 86 : 104,
            height: compact ? 86 : 104,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              color: scheme.primary.withValues(alpha: 0.12),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
            ),
            child: Icon(
              page.icon,
              color: scheme.primary,
              size: compact ? 42 : 50,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tomorrow',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '7:00 AM',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                WakeStatusPill(
                  label: page.eyebrow,
                  icon: page.icon,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingDetailCard extends StatelessWidget {
  final _OnboardingPage page;

  const _OnboardingDetailCard({required this.page});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shadows: wakeCardShadow(context),
      child: Column(
        children: [
          for (var i = 0; i < page.bullets.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: Theme.of(context).dividerColor),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Icon(Icons.check_rounded, color: scheme.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      page.bullets[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Circular glass halo behind the page's SF-style symbol, echoing the native
/// onboarding hero: a tinted accent disc with a hairline ring.
class _IconHero extends StatelessWidget {
  final IconData icon;
  final bool compact;

  const _IconHero({required this.icon, required this.compact});

  @override
  Widget build(BuildContext context) {
    final glass = GlassTheme.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final dimension = compact ? 112.0 : 150.0;
    return Container(
      width: dimension,
      height: dimension,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            primary.withValues(
              alpha: glass.brightness == Brightness.dark ? 0.20 : 0.14,
            ),
            primary.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(color: glass.stroke),
      ),
      child: Icon(icon, color: primary, size: compact ? 50 : 68),
    );
  }
}

class _OnboardingProfileView extends StatefulWidget {
  final Future<void> Function() onContinue;

  const _OnboardingProfileView({required this.onContinue});

  @override
  State<_OnboardingProfileView> createState() => _OnboardingProfileViewState();
}

class _OnboardingProfileViewState extends State<_OnboardingProfileView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _OnboardingAuthMode _mode = _OnboardingAuthMode.create;

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
    final colorScheme = Theme.of(context).colorScheme;
    final compactHeight = MediaQuery.sizeOf(context).height < 740;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, compactHeight ? 6 : 16, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: _IconHero(
              icon: Icons.person_add_alt_1_rounded,
              compact: compactHeight,
            ),
          ),
          SizedBox(height: compactHeight ? 20 : 28),
          Text(
            'Profile',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Save your setup, or keep going locally.',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'A profile backs up your name, photo, and alarms. You can skip this and add one later.',
            style: TextStyle(
              fontSize: 16,
              height: 1.45,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          BlocConsumer<AccountCubit, AccountState>(
            listenWhen: (previous, current) =>
                previous.message != current.message && current.message != null,
            listener: (context, state) {
              ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(content: Text(state.message!)));
            },
            builder: (context, state) {
              if (state.isInitializing) {
                return _profileShell(
                  context,
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                );
              }
              if (!state.firebaseReady) {
                return _firebaseUnavailableCard(context, state);
              }
              if (state.isSignedIn) {
                return _signedInCard(context, state);
              }
              return _authCard(context, state);
            },
          ),
        ],
      ),
    );
  }

  Widget _profileShell(BuildContext context, {required Widget child}) {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      shadows: wakeCardShadow(context),
      child: child,
    );
  }

  Widget _firebaseUnavailableCard(BuildContext context, AccountState state) {
    final scheme = Theme.of(context).colorScheme;
    return _profileShell(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_rounded, color: scheme.primary, size: 32),
          const SizedBox(height: 14),
          Text(
            'Account setup is unavailable',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            state.message ?? 'Firebase is still starting up.',
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

  Widget _signedInCard(BuildContext context, AccountState state) {
    return AccountProfileEditor(
      state: state,
      primaryActionLabel: 'Continue to Setup',
      primaryActionIcon: Icons.arrow_forward_rounded,
      onPrimaryAction: widget.onContinue,
      secondaryActionLabel: 'Use Another Account',
      secondaryActionIcon: Icons.switch_account_rounded,
      onSecondaryAction: () => context.read<AccountCubit>().signOut(),
    );
  }

  Widget _authCard(BuildContext context, AccountState state) {
    final scheme = Theme.of(context).colorScheme;
    final isCreate = _mode == _OnboardingAuthMode.create;
    return _profileShell(
      context,
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
          const _OnboardingAuthDivider(label: 'or use email'),
          const SizedBox(height: 18),
          SegmentedButton<_OnboardingAuthMode>(
            segments: const [
              ButtonSegment(
                value: _OnboardingAuthMode.create,
                label: Text('Create'),
              ),
              ButtonSegment(
                value: _OnboardingAuthMode.signIn,
                label: Text('Sign In'),
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 18),
          WakePrimaryButton(
            label: state.isBusy
                ? 'Please Wait...'
                : (isCreate ? 'Create Profile' : 'Sign In'),
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
          if (state.message != null) ...[
            const SizedBox(height: 12),
            _InlineAuthMessage(message: state.message!),
          ],
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
    if (_mode == _OnboardingAuthMode.create) {
      cubit.createAccount(email: email, password: password);
    } else {
      cubit.signIn(email: email, password: password);
    }
  }
}

class _OnboardingAuthDivider extends StatelessWidget {
  final String label;

  const _OnboardingAuthDivider({required this.label});

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

class _InlineAuthMessage extends StatelessWidget {
  final String message;

  const _InlineAuthMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.error.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: scheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingFooter extends StatelessWidget {
  final int selectedPage;
  final int pageCount;
  final bool isLastPage;
  final bool isProfileLeadIn;
  final bool isProfilePage;
  final VoidCallback onSkip;
  final VoidCallback onContinue;

  /// Optional "Set up this device as the clock" action, shown as a secondary box
  /// on the no-clock beta page. Null hides it.
  final VoidCallback? onSetupDedicatedClock;

  const _OnboardingFooter({
    required this.selectedPage,
    required this.pageCount,
    required this.isLastPage,
    required this.isProfileLeadIn,
    required this.isProfilePage,
    required this.onSkip,
    required this.onContinue,
    this.onSetupDedicatedClock,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            pageCount,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: selectedPage == index ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: selectedPage == index
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!isProfilePage)
          WakePrimaryButton(
            label: isProfileLeadIn ? 'Create Profile' : 'Continue',
            icon: isProfileLeadIn
                ? Icons.person_add_alt_1_rounded
                : Icons.arrow_right_alt_rounded,
            onPressed: onContinue,
          ),
        if (onSetupDedicatedClock != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: WakeSecondaryButton(
              label: 'Set up this device as the clock',
              icon: Icons.phonelink_ring_rounded,
              onPressed: onSetupDedicatedClock,
            ),
          ),
        if (!isLastPage || isProfilePage)
          Padding(
            padding: EdgeInsets.only(top: isProfilePage ? 2 : 6),
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant,
                minimumSize: Size(0, isProfilePage ? 34 : 44),
                padding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: isProfilePage ? 4 : 8,
                ),
                textStyle: TextStyle(
                  fontSize: isProfilePage ? 12.5 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Skip for now'),
            ),
          ),
      ],
    );
  }
}

class _PreparingOverlay extends StatelessWidget {
  const _PreparingOverlay();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.54),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: GlassCard(
                padding: const EdgeInsets.all(24),
                shadows: wakeCardShadow(context),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 18),
                    Text(
                      'Preparing WakeGuard',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Setting up your wake challenge and pairing flow.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
