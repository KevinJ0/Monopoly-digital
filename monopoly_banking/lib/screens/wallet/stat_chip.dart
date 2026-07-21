import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';

class StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const StatChip({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: kTextSecondary, fontSize: 9, letterSpacing: 0.8)),
      ],
    );
  }
}
