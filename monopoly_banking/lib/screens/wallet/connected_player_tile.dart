import 'package:flutter/material.dart';
import 'package:monopoly_banking/core/constants.dart';

class ConnectedPlayerTile extends StatelessWidget {
  final String displayName;
  final String avatar;
  final String role;
  final Color roleColor;
  final bool connected;
  final VoidCallback? onTap;

  const ConnectedPlayerTile({
    super.key,
    required this.displayName,
    required this.avatar,
    required this.role,
    required this.roleColor,
    this.connected = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: kBgCard,
      leading: CircleAvatar(
        backgroundColor: roleColor.withValues(alpha: 0.15),
        child: Text(avatar, style: TextStyle(fontSize: 20, color: roleColor)),
      ),
      title: Text(displayName, style: const TextStyle(color: kTextPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text(role, style: TextStyle(color: kTextSecondary, fontSize: 12)),
      trailing: Icon(
        connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
        color: connected ? kGreen : kRed,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}
