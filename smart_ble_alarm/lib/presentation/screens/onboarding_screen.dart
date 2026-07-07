import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/wake_widgets.dart';
import 'setup_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final SharedPreferences prefs;

  const OnboardingScreen({super.key, required this.prefs});

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
      eyebrow: 'WakeGuard',
      title: 'Wake up with a real first step.',
      body:
          'WakeGuard is built for people who need more than a bedside button. It pairs with a smart alarm clock and turns waking up into a short, intentional routine.',
      icon: Icons.wb_sunny_outlined,
      bullets: [
        'Designed for hard mornings',
        'Built around movement',
        'Made to reduce accidental dismissals',
      ],
    ),
    _OnboardingPage(
      eyebrow: 'Why it matters',
      title: 'Oversleeping is not just a willpower problem.',
      body:
          'Narcolepsy, severe sleep inertia, medication schedules, and chronic oversleeping can make alarms easy to miss or dismiss without fully waking up.',
      icon: Icons.bedtime_outlined,
      bullets: [
        'Sleeping through alarms',
        'Waking up confused or groggy',
        'Turning alarms off on autopilot',
      ],
    ),
    _OnboardingPage(
      eyebrow: 'How it helps',
      title: 'Dismissal requires proof you are up.',
      body:
          'When a protected alarm rings, WakeGuard asks you to leave bed and verify a real object in your home before the alarm can be dismissed.',
      icon: Icons.center_focus_strong,
      bullets: [
        'Choose an object away from bed',
        'Verify it with AI image recognition',
        'Build a repeatable morning path',
      ],
    ),
    _OnboardingPage(
      eyebrow: 'Personalize',
      title: 'Pick a wake object per alarm.',
      body:
          'When you create a protected alarm, you choose what to verify — like a bathroom sink, toothbrush, coffee maker, or medication — right in the alarm editor.',
      icon: Icons.auto_awesome,
      bullets: [
        'Set it per alarm in the editor',
        'Use an object that starts your routine',
        'Keep it far enough away to get moving',
      ],
    ),
    _OnboardingPage(
      eyebrow: 'Setup',
      title: 'Then connect your WakeGuard clock.',
      body:
          'After onboarding, the app will prepare the verification setup and search for your clock so alarms, time, and settings can stay synchronized.',
      icon: Icons.bluetooth_connected,
      bullets: [
        'Bluetooth sync for alarms',
        'Camera access for verification',
        'Clear loading states during setup',
      ],
    ),
  ];

  bool get _isLastPage => _selectedPage == _pages.length - 1;

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
    await widget.prefs.setBool(_hasSeenOnboardingKey, true);
    await Future<void>.delayed(const Duration(milliseconds: 850));

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: animation,
          child: SetupScreen(prefs: widget.prefs),
        ),
      ),
    );
  }

  Future<void> _skip() async {
    setState(() => _isPreparing = true);
    await widget.prefs.setBool(_hasSeenOnboardingKey, true);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SetupScreen(prefs: widget.prefs)),
    );
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
                      pageCount: _pages.length,
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _pages.length,
                      onPageChanged: (index) =>
                          setState(() => _selectedPage = index),
                      itemBuilder: (context, index) {
                        return _OnboardingPageView(page: _pages[index]);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    child: _OnboardingFooter(
                      selectedPage: _selectedPage,
                      pageCount: _pages.length,
                      isLastPage: _isLastPage,
                      onSkip: _skip,
                      onContinue: _continue,
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
  final String eyebrow;
  final String title;
  final String body;
  final IconData icon;
  final List<String> bullets;

  const _OnboardingPage({
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
    return Row(
      children: [
        const WakeLogoMark(size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WakeGuard',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Step $currentPage of $pageCount',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  final _OnboardingPage page;

  const _OnboardingPageView({
    required this.page,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final compactHeight = MediaQuery.sizeOf(context).height < 700;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, compactHeight ? 8 : 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _IconHero(icon: page.icon, compact: compactHeight)),
          SizedBox(height: compactHeight ? 22 : 32),
          Text(
            page.eyebrow.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            page.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            page.body,
            style: TextStyle(
              fontSize: 16,
              height: 1.45,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          ...page.bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      bullet,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
            primary.withValues(alpha: glass.brightness == Brightness.dark
                ? 0.20
                : 0.14),
            primary.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(color: glass.stroke),
      ),
      child: Icon(
        icon,
        color: primary,
        size: compact ? 50 : 68,
      ),
    );
  }
}

class _OnboardingFooter extends StatelessWidget {
  final int selectedPage;
  final int pageCount;
  final bool isLastPage;
  final VoidCallback onSkip;
  final VoidCallback onContinue;

  const _OnboardingFooter({
    required this.selectedPage,
    required this.pageCount,
    required this.isLastPage,
    required this.onSkip,
    required this.onContinue,
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
        WakePrimaryButton(
          label: isLastPage ? 'Prepare WakeGuard' : 'Continue',
          icon: isLastPage
              ? Icons.arrow_forward_rounded
              : Icons.arrow_right_alt_rounded,
          onPressed: onContinue,
        ),
        if (!isLastPage)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant,
                minimumSize: const Size(0, 44),
                textStyle: const TextStyle(
                  fontSize: 14,
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
