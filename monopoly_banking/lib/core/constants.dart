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
  if (!value.isFinite) return '0';

  final negative = value < 0;
  final text = value.abs().round().toString();

  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }

  return '${negative ? '-' : ''}${buffer.toString()}';
}

String formatMoney(num value) => '$kMoneySymbol${formatMoneyAmount(value)}';
