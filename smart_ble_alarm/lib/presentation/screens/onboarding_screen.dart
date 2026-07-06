import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/challenge/wake_challenge_options.dart';
import '../blocs/settings_bloc/settings_bloc.dart';
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
      title: 'Choose a wake object.',
      body:
          'Pick something you naturally interact with in the morning, like a bathroom sink, toothbrush, coffee maker, or medication.',
      icon: Icons.auto_awesome,
      bullets: [
        'Editable any time in Settings',
        'Use an object that starts your routine',
        'Keep it far enough away to get moving',
      ],
      showsWakeObjectPicker: true,
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

  void _showWakeObjectSheet(SettingsState settingsState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Choose wake object',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              ...WakeChallengeOptions.suggestedObjects.map(
                (option) => ListTile(
                  title: Text(option),
                  trailing: settingsState.wakeObjectName == option
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    context.read<SettingsBloc>().add(
                      UpdateWakeObjectEvent(option),
                    );
                    Navigator.pop(sheetContext);
                  },
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.edit,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Custom object'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCustomWakeObjectDialog(settingsState.wakeObjectName);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCustomWakeObjectDialog(String currentValue) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Custom wake object'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Bathroom sink, coffee maker, medication...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                context.read<SettingsBloc>().add(
                  UpdateWakeObjectEvent(controller.text),
                );
                Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: Theme.of(context).brightness == Brightness.dark
                ? const [Color(0xFF0F111A), Colors.black]
                : const [Color(0xFFF3F4F6), Colors.white],
          ),
        ),
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
                        return _OnboardingPageView(
                          page: _pages[index],
                          onChooseWakeObject: () => _showWakeObjectSheet(
                            context.read<SettingsBloc>().state,
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
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
  final bool showsWakeObjectPicker;

  const _OnboardingPage({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.icon,
    required this.bullets,
    this.showsWakeObjectPicker = false,
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
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/branding/wakeguard_logo.png',
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WakeGuard',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(
                'Step $currentPage of $pageCount',
                style: Theme.of(context).textTheme.bodySmall,
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
  final VoidCallback onChooseWakeObject;

  const _OnboardingPageView({
    required this.page,
    required this.onChooseWakeObject,
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
          Center(
            child: Container(
              width: compactHeight ? 112 : 148,
              height: compactHeight ? 112 : 148,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                page.icon,
                color: colorScheme.primary,
                size: compactHeight ? 54 : 72,
              ),
            ),
          ),
          SizedBox(height: compactHeight ? 22 : 32),
          Text(
            page.eyebrow.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            page.title,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            page.body,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 22),
          ...page.bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bullet,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (page.showsWakeObjectPicker) ...[
            const SizedBox(height: 10),
            BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                return Material(
                  color: colorScheme.surface.withValues(alpha: 0.74),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: onChooseWakeObject,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.center_focus_strong,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Wake object',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  settingsState.wakeObjectName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
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
              duration: const Duration(milliseconds: 240),
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
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onContinue,
            icon: Icon(
              isLastPage ? Icons.arrow_forward : Icons.arrow_right_alt,
            ),
            label: Text(
              isLastPage ? 'Prepare WakeGuard' : 'Continue',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        if (!isLastPage)
          TextButton(onPressed: onSkip, child: const Text('Skip for now')),
      ],
    );
  }
}

class _PreparingOverlay extends StatelessWidget {
  const _PreparingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.58),
          child: Center(
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Preparing WakeGuard',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Setting up your wake challenge and pairing flow.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
