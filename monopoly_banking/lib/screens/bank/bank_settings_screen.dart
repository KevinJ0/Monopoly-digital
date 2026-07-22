import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/bank_settings_service.dart';
import 'package:monopoly_banking/core/game_transitions.dart';

class BankSettingsScreen extends StatefulWidget {
  const BankSettingsScreen({super.key});

  @override
  State<BankSettingsScreen> createState() => _BankSettingsScreenState();
}

class _BankSettingsScreenState extends State<BankSettingsScreen> {
  final _settings = BankSettingsService();
  late TextEditingController _initialCtrl;
  late TextEditingController _passGoCtrl;

  @override
  void initState() {
    super.initState();
    _initialCtrl = TextEditingController(
        text: _settings.initialBalance.round().toString());
    _passGoCtrl =
        TextEditingController(text: _settings.passGoAmount.round().toString());
  }

  @override
  void dispose() {
    _initialCtrl.dispose();
    _passGoCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final initial =
        double.tryParse(_initialCtrl.text.replaceAll(',', '')) ?? 2000.0;
    final passGo =
        double.tryParse(_passGoCtrl.text.replaceAll(',', '')) ?? 200.0;
    _settings.initialBalance = initial;
    _settings.passGoAmount = passGo;
    await _settings.save();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBgDark,
        title: const Text('Configuración',
            style: TextStyle(
                color: kTextPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: kTextPrimary),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Guardar',
                style: TextStyle(
                    color: kGold,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGeneralSection(),
            const SizedBox(height: 32),
            _buildCustomOpsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.tune_rounded, color: kGold, size: 20),
            const SizedBox(width: 10),
            const Text('CONFIGURACIÓN GENERAL',
                style: TextStyle(
                    color: kTextSecondary,
                    fontSize: 11,
                    letterSpacing: 2)),
          ],
        ),
        const SizedBox(height: 16),
        _buildSettingCard([
          _buildAmountField(
            label: 'Monto inicial del handshake',
            subtitle: 'Cantidad con la que empieza cada jugador',
            icon: Icons.handshake_rounded,
            controller: _initialCtrl,
          ),
          const SizedBox(height: 12),
          _buildAmountField(
            label: 'Pasar por GO',
            subtitle: 'Cantidad que recibe el jugador al pasar por GO',
            icon: Icons.flag_rounded,
            controller: _passGoCtrl,
          ),
        ]),
      ],
    );
  }

  Widget _buildSettingCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kBgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildAmountField({
    required String label,
    required String subtitle,
    required IconData icon,
    required TextEditingController controller,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: kGold, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: kTextPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      color: kTextSecondary, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: kGold, fontSize: 18, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              prefixText: '\$ ',
              prefixStyle: const TextStyle(
                  color: kGold, fontSize: 18, fontWeight: FontWeight.w800),
              filled: true,
              fillColor: Colors.black26,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kGold, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomOpsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.add_circle_outline_rounded,
                color: kGold, size: 20),
            const SizedBox(width: 10),
            const Text('OPERACIONES PERSONALIZADAS',
                style: TextStyle(
                    color: kTextSecondary,
                    fontSize: 11,
                    letterSpacing: 2)),
          ],
        ),
        const SizedBox(height: 16),
        ..._settings.customOps.asMap().entries.map((entry) {
          final i = entry.key;
          final op = entry.value;
          final iconData =
              BankSettingsService.availableIcons[op.iconKey] ?? Icons.payments_rounded;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Dismissible(
              key: ValueKey(op.id),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) async {
                return await showGameDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: kBgCard,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('Eliminar operación',
                        style: TextStyle(color: kTextPrimary)),
                    content: Text(
                      '¿Eliminar "${op.name}"?',
                      style: const TextStyle(color: kTextSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar', style: TextStyle(color: kTextSecondary)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Eliminar', style: TextStyle(color: kRed)),
                      ),
                    ],
                  ),
                );
              },
              onDismissed: (_) {
                setState(() => _settings.customOps.removeAt(i));
                _settings.save();
              },
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: kRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.delete_rounded, color: kRed, size: 24),
              ),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: kBgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _editCustomOp(i),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: kGold.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(iconData, color: kGold, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(op.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: kTextPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: (op.isGive ? kGreen : kRed)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        op.isGive
                                            ? '+${formatMoney(op.amount)}'
                                            : '-${formatMoney(op.amount)}',
                                        style: TextStyle(
                                          color: op.isGive ? kGreen : kRed,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      op.isGive ? 'Dar' : 'Quitar',
                                      style: const TextStyle(
                                          color: kTextSecondary, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => _deleteCustomOp(i),
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: kRed, size: 20),
                            splashRadius: 20,
                            tooltip: 'Eliminar',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addCustomOp,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Agregar operación',
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: kGold,
              side: const BorderSide(color: kGold),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addCustomOp() async {
    final result = await _showCustomOpDialog();
    if (result != null) {
      setState(() => _settings.customOps.add(result));
      await _settings.save();
    }
  }

  Future<void> _editCustomOp(int index) async {
    final op = _settings.customOps[index];
    final result = await _showCustomOpDialog(existing: op);
    if (result != null) {
      setState(() => _settings.customOps[index] = result);
      await _settings.save();
    }
  }

  Future<void> _deleteCustomOp(int index) async {
    final op = _settings.customOps[index];
    final confirm = await showGameDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar operación',
            style: TextStyle(color: kTextPrimary)),
        content: Text(
          '¿Eliminar "${op.name}"?',
          style: const TextStyle(color: kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: kTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _settings.customOps.removeAt(index));
      await _settings.save();
    }
  }

  Future<CustomOperation?> _showCustomOpDialog({CustomOperation? existing}) async {
    final nameCtrl =
        TextEditingController(text: existing?.name ?? '');
    final amountCtrl = TextEditingController(
        text: existing != null ? existing.amount.round().toString() : '');
    final isGive = ValueNotifier<bool>(existing?.isGive ?? true);
    final selectedIcon = ValueNotifier<String>(existing?.iconKey ?? 'payments_rounded');

    final saved = await showGameDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: kBgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(existing != null ? 'Editar operación' : 'Nueva operación',
              style: const TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 17)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nombre',
                      style:
                          TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: nameCtrl,
                    style: const TextStyle(color: kTextPrimary, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Ej: Compra de propiedad',
                      hintStyle: const TextStyle(color: kBorder),
                      filled: true,
                      fillColor: Colors.black26,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kGold, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('MONTO',
                      style:
                          TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                        color: kGold, fontSize: 22, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      prefixStyle: const TextStyle(
                          color: kGold,
                          fontSize: 22,
                          fontWeight: FontWeight.w800),
                      filled: true,
                      fillColor: Colors.black26,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kGold, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('TIPO',
                      style:
                          TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: isGive,
                    builder: (_, give, __) => Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => isGive.value = true,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: give
                                    ? kGreen.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: give ? kGreen : kBorder,
                                  width: give ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_circle_outline_rounded,
                                      color: give ? kGreen : kTextSecondary,
                                      size: 20),
                                  const SizedBox(width: 8),
                                  Text('Dar',
                                      style: TextStyle(
                                          color: give ? kGreen : kTextSecondary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => isGive.value = false,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !give
                                    ? kRed.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: !give ? kRed : kBorder,
                                  width: !give ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.remove_circle_outline_rounded,
                                      color: !give ? kRed : kTextSecondary,
                                      size: 20),
                                  const SizedBox(width: 8),
                                  Text('Quitar',
                                      style: TextStyle(
                                          color: !give ? kRed : kTextSecondary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('ICONO',
                      style:
                          TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: selectedIcon,
                    builder: (_, iconKey, __) {
                      final entries = BankSettingsService.availableIcons.entries.toList();
                      final itemsPerRow = 6;
                      final rows = <List<MapEntry<String, IconData>>>[];
                      for (var i = 0; i < entries.length; i += itemsPerRow) {
                        rows.add(
                            entries.sublist(i, min(i + itemsPerRow, entries.length)));
                      }
                      return Column(
                        children: rows.map((row) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: row.map((entry) {
                                final selected = entry.key == iconKey;
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () => selectedIcon.value = entry.key,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 3),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? kGold.withValues(alpha: 0.15)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: selected ? kGold : kBorder,
                                          width: selected ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Icon(entry.value,
                                          color: selected ? kGold : kTextSecondary,
                                          size: 22),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar',
                  style: TextStyle(color: kTextSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final amountText = amountCtrl.text.trim();
                if (name.isEmpty || amountText.isEmpty) return;
                final amount = double.tryParse(amountText) ?? 0;
                if (amount <= 0) return;
                Navigator.of(ctx).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Guardar',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return null;

    final id = existing?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    return CustomOperation(
      id: id,
      name: nameCtrl.text.trim(),
      amount: amount,
      isGive: isGive.value,
      iconKey: selectedIcon.value,
    );
  }
}
