import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/providers/balance_tween_controller.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/screens/role_selection_screen.dart';
import 'package:monopoly_banking/screens/wallet_screen.dart';
import 'package:monopoly_banking/screens/splash_screen.dart';
import 'package:monopoly_banking/services/notification_service.dart';

class MonopolyApp extends StatefulWidget {
  const MonopolyApp({super.key});

  @override
  State<MonopolyApp> createState() => _MonopolyAppState();
}

class _MonopolyAppState extends State<MonopolyApp> {
  late final StatsProvider _stats;
  late final WalletController _wallet;
  late final SessionProvider _session;
  late final BalanceTweenController _tween;

  @override
  void initState() {
    super.initState();
    _stats = StatsProvider();
    _wallet = WalletController(_stats);
    _session = SessionProvider(_stats, _wallet);
    _tween = BalanceTweenController();
    _session.restoreSession();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<StatsProvider>.value(value: _stats),
        ChangeNotifierProvider<WalletController>.value(value: _wallet),
        ChangeNotifierProvider<SessionProvider>.value(value: _session),
        Provider<BalanceTweenController>.value(value: _tween),
      ],
      child: MaterialApp(
        scaffoldMessengerKey: NotificationService().scaffoldMessengerKey,
        title: 'Monopoly Banking',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: kBgDark,
          colorScheme: const ColorScheme.dark(
            primary: kGreen,
            secondary: kGold,
            surface: kBgCard,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: kBgDark,
            elevation: 0,
            iconTheme: IconThemeData(color: kTextSecondary),
            titleTextStyle: TextStyle(
              color: kTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          textTheme: const TextTheme(
            bodyMedium: TextStyle(color: kTextPrimary),
          ),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            },
          ),
        ),
        home: const _RootRouter(),
      ),
    );
  }
}

class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _takeHome();
  }

  Future<void> _takeHome() async {
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      setState(() => _showSplash = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return const SplashScreen();
    }

    final session = context.watch<SessionProvider>();

    if (!session.initialized) {
      return const Scaffold(
        backgroundColor: kBgDark,
        body: Center(
          child: CircularProgressIndicator(color: kGreen),
        ),
      );
    }

    final hasSession = session.role.isNotEmpty && session.avatarId.isNotEmpty;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      child: hasSession
          ? const WalletScreen(key: ValueKey('wallet'))
          : const RoleSelectionScreen(key: ValueKey('role')),
    );
  }
}
