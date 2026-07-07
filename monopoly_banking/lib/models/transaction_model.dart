import 'package:hive/hive.dart';

part 'transaction_model.g.dart';

@HiveType(typeId: 0)
class TransactionModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String type;

  @HiveField(2)
  final double amount;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  final String? counterpartyId;

  @HiveField(5)
  final double balanceAfter;

  TransactionModel({
    required this.id,
    required this.type,
    required this.amount,
    required this.timestamp,
    this.counterpartyId,
    required this.balanceAfter,
  });
}
