import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:money_manager/core/constants.dart';
import 'package:money_manager/core/theme.dart';
import 'package:money_manager/providers/balance_tween_controller.dart';
import 'package:money_manager/providers/session_provider.dart';
import 'package:money_manager/widgets/app_spinner.dart';
import 'package:money_manager/providers/stats_provider.dart';
import 'package:money_manager/providers/wallet_controller.dart';
import 'package:money_manager/screens/role_selection_screen.dart';
import 'package:money_manager/screens/player_screen.dart';
import 'package:money_manager/screens/bank_home_screen.dart';
import 'package:money_manager/screens/splash_screen.dart';
import 'package:money_manager/services/notification_service.dart';
import 'package:money_manager/services/bank_settings_service.dart';
import 'package:money_manager/services/bank_ledger_service.dart';
import 'package:money_manager/services/hive_service.dart';

class MoneyManagerApp extends StatefulWidget {
  const MoneyManagerApp({super.key});

  @override
  State<MoneyManagerApp> createState() => _MoneyManagerAppState();
}

class _MoneyManagerAppState extends State<MoneyManagerApp> {
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
      title: 'Money Manager',
      debugShowCheckedModeBanner: false,
      theme: moneyManagerTheme(),
      home: const _RootRouter(),
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
    await Future.delayed(const Duration(seconds: 2));

    // Pre-warm bank caches while splash is still visible
    final session = HiveService.sessionBox.get('current');
    if (session != null && session.role == 'banco') {
      BankSettingsService().load();
      BankLedgerService().transactionHistory;
    }

    await Future.delayed(const Duration(seconds: 1));
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
    Widget screen;
    if (hasSession) {
      if (session.isBank) {
        screen = const BankHomeScreen(key: ValueKey('bank_home'));
      } else {
        screen = const PlayerScreen(key: ValueKey('player'));
      }
    } else {
      screen = const RoleSelectionScreen(key: ValueKey('role'));
    }

    return screen;
  }
}
