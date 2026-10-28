import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/realtime/events_socket.dart';
import '../data/models.dart';
import '../features/account/account_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/confirm/confirm_screen.dart';
import '../features/history/history_screens.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/subscription/subscription_screen.dart';
import '../features/trip/trip_screen.dart';
import '../shared/widgets.dart';
import 'providers.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, __) => refresh.value++);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.isLoading || auth.hasError) return state.matchedLocation == '/splash' ? null : '/splash';
      final signedIn = auth.valueOrNull != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      if (atLogin || state.matchedLocation == '/splash') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _Splash()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => _Shell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/rides', builder: (_, __) => const HistoryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/earnings', builder: (_, __) => const EarningsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/account', builder: (_, __) => const AccountScreen())]),
        ],
      ),
      GoRoute(path: '/ride/:id', builder: (_, s) => TripScreen(rideId: s.pathParameters['id']!)),
      GoRoute(path: '/confirm/:id', builder: (_, s) => ConfirmRideScreen(rideId: s.pathParameters['id']!)),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/subscription', builder: (_, __) => const SubscriptionScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
    ],
  );
});

class DriverApp extends ConsumerStatefulWidget {
  const DriverApp({super.key});
  @override
  ConsumerState<DriverApp> createState() => _DriverAppState();
}

class _DriverAppState extends ConsumerState<DriverApp> with WidgetsBindingObserver {
  Timer? _reconcile;
  String? _shownMatch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Server reconciliation of "waiting for my confirmation": hints are fast, this guarantees correctness.
    _reconcile = Timer.periodic(const Duration(seconds: 15), (_) {
      if (ref.read(authProvider).valueOrNull != null) ref.read(pendingMatchProvider.notifier).reconcile();
    });
  }

  @override
  void dispose() {
    _reconcile?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A rider selected this driver: bring the confirmation screen up wherever the driver is (once per selection).
  void _openConfirmation(Ride ride) {
    final key = '${ride.id}@${ride.version}';
    if (_shownMatch == key) return;
    _shownMatch = key;
    final router = ref.read(routerProvider);
    final path = router.routerDelegate.currentConfiguration.uri.path;
    if (path != '/confirm/${ride.id}') router.push('/confirm/${ride.id}');
  }

  /// Back in the foreground: reconnect the event stream now and re-read state that may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ref.read(authProvider).valueOrNull != null) {
      ref.read(eventsSocketProvider).reconnectNow();
      ref.read(pendingMatchProvider.notifier).reconcile();
      ref.read(onlineControllerProvider.notifier).recheckAccess();
      ref.invalidate(eligibilityProvider);
      ref.invalidate(offersProvider);
      ref.invalidate(ridesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    ref.watch(realtimeBridgeProvider);
    ref.listen(authProvider, (prev, next) {
      final socket = ref.read(eventsSocketProvider);
      if (next.valueOrNull != null) {
        unawaited(socket.start());
        ref.invalidate(pendingMatchProvider); // restore a pending confirmation after sign-in / restart
      } else if (prev?.valueOrNull != null) {
        unawaited(socket.stop());
      }
    });
    ref.listen(pendingMatchProvider, (_, next) {
      final ride = next.valueOrNull;
      if (ride != null) _openConfirmation(ride);
    });
    return MaterialApp.router(
      onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildRideFlowTheme(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _Shell extends ConsumerWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final socket = ref.watch(socketStateProvider).valueOrNull;
    return Scaffold(
      body: Column(children: [
        if (socket == SocketState.disconnected)
          Material(
            color: RfColors.amberSoft,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(children: [
                  const Icon(Icons.cloud_off_rounded, size: 16, color: RfColors.amber),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.offlineBanner, style: const TextStyle(fontSize: 12))),
                ]),
              ),
            ),
          ),
        Expanded(child: shell),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: t.navHome),
          NavigationDestination(icon: const Icon(Icons.route_outlined), selectedIcon: const Icon(Icons.route), label: t.navRides),
          NavigationDestination(icon: const Icon(Icons.payments_outlined), selectedIcon: const Icon(Icons.payments), label: t.navEarnings),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: t.navAccount),
        ],
      ),
    );
  }
}

class _Splash extends ConsumerWidget {
  const _Splash();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      body: auth.hasError ? ErrorView(error: auth.error!, onRetry: () => ref.invalidate(authProvider)) : const LoadingView(),
    );
  }
}
