import 'package:hive/hive.dart';

part 'session_model.g.dart';

@HiveType(typeId: 1)
class SessionModel extends HiveObject {
  @HiveField(0)
  String role;

  @HiveField(1)
  double balance;

  @HiveField(2)
  String avatarId;

  @HiveField(3)
  String colorId;

  @HiveField(4)
  bool isBankrupt;

  @HiveField(5)
  double totalVolume;

  @HiveField(6)
  int txCount;

  @HiveField(7)
  int passGoCount;

  @HiveField(8)
  final String? name;
  @HiveField(9)
  final bool isHandshakeDone;

  @HiveField(10, defaultValue: 0.0)
  double vaultInvestedAmount;

  @HiveField(11)
  List<double> balanceHistory;

  @HiveField(12, defaultValue: 0.0)
  double vaultGeneratedAmount;

  @HiveField(13, defaultValue: 0)
  int vaultTargetPasses;

  @HiveField(14, defaultValue: 0)
  int vaultCurrentPasses;

  @HiveField(15, defaultValue: 0)
  int maxTier;

  SessionModel({
    required this.role,
    required this.balance,
    required this.avatarId,
    required this.colorId,
    this.totalVolume = 0.0,
    this.txCount = 0,
    this.passGoCount = 0,
    this.isBankrupt = false,
    this.name,
    this.isHandshakeDone = false,
    this.vaultInvestedAmount = 0.0,
    this.vaultGeneratedAmount = 0.0,
    this.vaultTargetPasses = 0,
    this.vaultCurrentPasses = 0,
    this.maxTier = 0,
    List<double>? balanceHistory,
  }) : balanceHistory = balanceHistory ?? [];
}
