import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/realtime/events_socket.dart';
import '../data/models.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../features/account/account_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/history/history_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/home/home_screen.dart';
import '../features/request/destination_screen.dart';
import '../features/waits/wait_times_screen.dart';
import '../features/request/request_screen.dart';
import '../features/ride/ride_screen.dart';
import '../shared/widgets.dart';
import 'providers.dart';

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
          StatefulShellBranch(routes: [GoRoute(path: '/account', builder: (_, __) => const AccountScreen())]),
        ],
      ),
      GoRoute(path: '/destination', builder: (_, s) => DestinationScreen(initialDropoff: s.extra as Place?)),
      GoRoute(path: '/request', builder: (_, s) => RequestScreen(draft: s.extra! as RideDraft)),
      GoRoute(path: '/ride/:id', builder: (_, s) => RideScreen(rideId: s.pathParameters['id']!)),
      GoRoute(path: '/receipt/:id', builder: (_, s) => ReceiptScreen(rideId: s.pathParameters['id']!)),
      GoRoute(path: '/places', builder: (_, __) => const PlacesScreen()),
      GoRoute(path: '/waits', builder: (_, __) => const WaitTimesScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
    ],
  );
});

void applyAppearanceToSystemBars() => SystemChrome.setSystemUIOverlayStyle(RfColors.isNight ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);

class RiderApp extends ConsumerStatefulWidget {
  const RiderApp({super.key});
  @override
  ConsumerState<RiderApp> createState() => _RiderAppState();
}

class _RiderAppState extends ConsumerState<RiderApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back in the foreground: reconnect the event stream now and re-read state that may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ref.read(authProvider).valueOrNull != null) {
      ref.read(eventsSocketProvider).reconnectNow();
      ref.invalidate(ridesProvider);
    }
  }

  /// Widgets read colours while building and don't depend on the theme for them, so a change has to reach all of them.
  void _rebuildEverything() {
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    if (mounted) (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(appearanceProvider);
    if (appearance != RfColors.appearance) {
      RfColors.use(appearance);
      applyAppearanceToSystemBars();
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildEverything());
    }
    final layout = ref.watch(layoutProvider);
    if (layout != RfLayout.model) {
      RfLayout.use(layout);
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildEverything());
    }
    ref.watch(realtimeBridgeProvider);
    ref.listen(authProvider, (prev, next) {
      final socket = ref.read(eventsSocketProvider);
      if (next.valueOrNull != null) {
        unawaited(socket.start());
      } else if (prev?.valueOrNull != null) {
        unawaited(socket.stop());
      }
    });
    return MaterialApp.router(
      onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildRideFlowTheme(family: ref.watch(fontProvider)),
      locale: ref.watch(localeProvider),
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
                  Icon(Icons.cloud_off_rounded, size: 16, color: RfColors.amber),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.offlineBanner, style: RfType.caption)),
                ]),
              ),
            ),
          ),
        Expanded(child: shell),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        backgroundColor: RfColors.ink2,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded, color: RfColors.teal), label: t.navHome),
          NavigationDestination(icon: const Icon(Icons.schedule_rounded), selectedIcon: Icon(Icons.schedule_rounded, color: RfColors.teal), label: t.navRides),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: Icon(Icons.person_rounded, color: RfColors.teal), label: t.navAccount),
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
      backgroundColor: RfColors.canvas,
      body: auth.hasError ? ErrorView(error: auth.error!, onRetry: () => ref.invalidate(authProvider)) : const Center(child: CircularProgressIndicator()),
    );
  }
}
