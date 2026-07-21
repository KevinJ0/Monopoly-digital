import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/core/theme.dart';
import 'package:monopoly_banking/providers/balance_tween_controller.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/widgets/app_spinner.dart';
import 'package:monopoly_banking/providers/stats_provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/screens/role_selection_screen.dart';
import 'package:monopoly_banking/screens/wallet_screen.dart';
import 'package:monopoly_banking/screens/bank_home_screen.dart';
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
      child: const _AppShell(),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: NotificationService().scaffoldMessengerKey,
      title: 'Monopoly Banking',
      debugShowCheckedModeBanner: false,
      theme: monopolyTheme(),
      home: const _RootRouter(),
    );
  }
}

class _ScreenLabel extends StatelessWidget {
  final String screen;
  const _ScreenLabel(this.screen);
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final role = session.isBank ? 'Banco' : (session.role == 'cliente' ? 'Cliente' : '—');
    final handshake = session.isHandshakeDone ? '' : ' · No handshake';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$screen · $role$handshake',
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
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
          child: AppSpinner(color: kGreen),
        ),
      );
    }

    final hasSession = session.role.isNotEmpty && session.avatarId.isNotEmpty;
    final childKey = hasSession
        ? (session.isBank ? 'bank_home' : 'wallet')
        : 'role';
    debugPrint('[┊] ROOT_ROUTER hasSession=$hasSession childKey=$childKey');

    String screenName;
    Widget screen;
    if (hasSession) {
      if (session.isBank) {
        screenName = 'BankHomeScreen';
        screen = const BankHomeScreen(key: ValueKey('bank_home'));
      } else {
        screenName = 'WalletScreen';
        screen = const WalletScreen(key: ValueKey('wallet'));
      }
    } else {
      screenName = 'RoleSelectionScreen';
      screen = const RoleSelectionScreen(key: ValueKey('role'));
    }

    return Stack(
      key: ValueKey('screen_$screenName'),
      children: [
        screen,
        Positioned(
          left: 8,
          bottom: 8,
          child: _ScreenLabel(screenName),
        ),
      ],
    );
  }
}
