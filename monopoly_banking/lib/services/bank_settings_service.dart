import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:monopoly_banking/services/hive_service.dart';

class CustomOperation {
  final String id;
  String name;
  double amount;
  bool isGive;
  String iconKey;

  CustomOperation({
    required this.id,
    required this.name,
    required this.amount,
    required this.isGive,
    required this.iconKey,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'isGive': isGive,
        'iconKey': iconKey,
      };

  factory CustomOperation.fromJson(Map<String, dynamic> json) =>
      CustomOperation(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Operación',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        isGive: json['isGive'] as bool? ?? true,
        iconKey: json['iconKey'] as String? ?? 'payments_rounded',
      );

  CustomOperation copyWith({
    String? id,
    String? name,
    double? amount,
    bool? isGive,
    String? iconKey,
  }) =>
      CustomOperation(
        id: id ?? this.id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        isGive: isGive ?? this.isGive,
        iconKey: iconKey ?? this.iconKey,
      );
}

class BankSettingsService {
  static final BankSettingsService _instance = BankSettingsService._();
  factory BankSettingsService() => _instance;
  BankSettingsService._();

  static const _key = 'bank_settings_v4';

  double initialBalance = 2000.0;
  double passGoAmount = 200.0;
  List<CustomOperation> customOps = [];

  static const Map<String, IconData> availableIcons = {
    'payments_rounded': Icons.payments_rounded,
    'account_balance_rounded': Icons.account_balance_rounded,
    'money_rounded': Icons.money_rounded,
    'shopping_cart_rounded': Icons.shopping_cart_rounded,
    'build_rounded': Icons.build_rounded,
    'car_rental_rounded': Icons.car_rental_rounded,
    'home_rounded': Icons.home_rounded,
    'hotel_rounded': Icons.hotel_rounded,
    'flight_rounded': Icons.flight_rounded,
    'train_rounded': Icons.train_rounded,
    'local_pizza_rounded': Icons.local_pizza_rounded,
    'celebration_rounded': Icons.celebration_rounded,
    'card_giftcard_rounded': Icons.card_giftcard_rounded,
    'redeem_rounded': Icons.redeem_rounded,
    'school_rounded': Icons.school_rounded,
    'health_and_safety_rounded': Icons.health_and_safety_rounded,
    'sports_esports_rounded': Icons.sports_esports_rounded,
    'handyman_rounded': Icons.handyman_rounded,
    'electric_bolt_rounded': Icons.electric_bolt_rounded,
    'diamond_rounded': Icons.diamond_rounded,
    'stars_rounded': Icons.stars_rounded,
    'emoji_events_rounded': Icons.emoji_events_rounded,
    'trending_up_rounded': Icons.trending_up_rounded,
    'trending_down_rounded': Icons.trending_down_rounded,
    'attach_money_rounded': Icons.attach_money_rounded,
    'savings_rounded': Icons.savings_rounded,
    'wallet_rounded': Icons.wallet_rounded,
    'receipt_long_rounded': Icons.receipt_long_rounded,
    'luggage_rounded': Icons.luggage_rounded,
    'directions_car_rounded': Icons.directions_car_rounded,
    'pedal_bike_rounded': Icons.pedal_bike_rounded,
    'directions_boat_rounded': Icons.directions_boat_rounded,
    'airplane_ticket_rounded': Icons.airplane_ticket_rounded,
    'business_rounded': Icons.business_rounded,
    'apartment_rounded': Icons.apartment_rounded,
    'cottage_rounded': Icons.cottage_rounded,
    'park_rounded': Icons.park_rounded,
    'water_drop_rounded': Icons.water_drop_rounded,
    'bolt_rounded': Icons.bolt_rounded,
    'whatshot_rounded': Icons.whatshot_rounded,
    'celebration_outlined': Icons.celebration_outlined,
    'cake_rounded': Icons.cake_rounded,
    'card_giftcard_outlined': Icons.card_giftcard_outlined,
  };

  Future<void> load() async {
    try {
      final raw = HiveService.settingsBox.get(_key) as String?;
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      initialBalance = (data['initialBalance'] as num?)?.toDouble() ?? 2000.0;
      passGoAmount = (data['passGoAmount'] as num?)?.toDouble() ?? 200.0;
      final ops = data['customOps'] as List<dynamic>?;
      if (ops != null) {
        customOps = ops
            .map((e) => CustomOperation.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
  }

  Future<void> save() async {
    final data = {
      'initialBalance': initialBalance,
      'passGoAmount': passGoAmount,
      'customOps': customOps.map((e) => e.toJson()).toList(),
    };
    await HiveService.settingsBox.put(_key, jsonEncode(data));
  }
}
