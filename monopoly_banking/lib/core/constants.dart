import 'package:flutter/material.dart';

const kBgDark = Color(0xFF0A0F1E);
const kBgCard = Color(0xFF111827);
const kGreen = Color(0xFF00C853);
const kGreenDark = Color(0xFF00892A);
const kGreenGlow = Color(0x3300C853);
const kGold = Color(0xFFFFD600);
const kRed = Color(0xFFFF4444);
const kTextPrimary = Color(0xFFFFFFFF);
const kTextSecondary = Color(0xFF9CA3AF);
const kBorder = Color(0xFF1F2937);

const kMoneySymbol = '\$';

const kInitialBalance = 2000.0;
const kPassGoAmount = 200.0;

String formatMoneyAmount(num value) {
  if (value.isInfinite) return '∞';
  if (value.isNaN) return 'NaN';

  final negative = value < 0;
  final absolute = value.abs();
  final hasDecimals = absolute % 1 != 0;
  var text =
      hasDecimals ? absolute.toStringAsFixed(2) : absolute.round().toString();
  if (hasDecimals) {
    text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  final parts = text.split('.');
  final whole = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }

  final decimals = parts.length > 1 ? '.${parts.last}' : '';
  return '${negative ? '-' : ''}${buffer.toString()}$decimals';
}

String formatMoney(num value) => '$kMoneySymbol${formatMoneyAmount(value)}';
