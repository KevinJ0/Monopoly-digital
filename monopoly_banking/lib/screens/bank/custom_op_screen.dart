import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/services/bank_settings_service.dart';
import 'package:monopoly_banking/widgets/animated_entry.dart';

class CustomOpScreen extends StatefulWidget {
  final CustomOperation? existing;

  const CustomOpScreen({super.key, this.existing});

  @override
  State<CustomOpScreen> createState() => _CustomOpScreenState();
}

class _CustomOpScreenState extends State<CustomOpScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late bool _isGive;
  late String _selectedIcon;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _amountCtrl = TextEditingController(
      text: widget.existing != null
          ? widget.existing!.amount.round().toString()
          : '',
    );
    _isGive = widget.existing?.isGive ?? true;
    _selectedIcon = widget.existing?.iconKey ?? 'payments_rounded';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final id = widget.existing?.id ??
        'custom_${DateTime.now().millisecondsSinceEpoch}';
    Navigator.of(context).pop(CustomOperation(
      id: id,
      name: _nameCtrl.text.trim(),
      amount: double.parse(_amountCtrl.text.trim()),
      isGive: _isGive,
      iconKey: _selectedIcon,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          widget.existing != null ? 'Editar operación' : 'Nueva operación',
          style: const TextStyle(
            color: kTextPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: kTextSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedEntry(
                delay: const Duration(milliseconds: 50),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('NOMBRE',
                        style: TextStyle(
                            color: kTextSecondary,
                            fontSize: 11,
                            letterSpacing: 2)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameCtrl,
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
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: kRed, width: 1.5),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: kRed, width: 1.5),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Ingresa un nombre';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              AnimatedEntry(
                delay: const Duration(milliseconds: 150),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('MONTO',
                        style: TextStyle(
                            color: kTextSecondary,
                            fontSize: 11,
                            letterSpacing: 2)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _amountCtrl,
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
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: kRed, width: 1.5),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: kRed, width: 1.5),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Ingresa un monto';
                        final amount = double.tryParse(v.trim());
                        if (amount == null || amount <= 0) {
                          return 'El monto debe ser mayor a 0';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              AnimatedEntry(
                delay: const Duration(milliseconds: 250),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TIPO',
                        style: TextStyle(
                            color: kTextSecondary,
                            fontSize: 11,
                            letterSpacing: 2)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _isGive = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _isGive
                                    ? kGreen.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _isGive ? kGreen : kBorder,
                                  width: _isGive ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_circle_outline_rounded,
                                      color: _isGive ? kGreen : kTextSecondary,
                                      size: 20),
                                  const SizedBox(width: 8),
                                  Text('Dar',
                                      style: TextStyle(
                                          color: _isGive ? kGreen : kTextSecondary,
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
                            onTap: () => setState(() => _isGive = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !_isGive
                                    ? kRed.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: !_isGive ? kRed : kBorder,
                                  width: !_isGive ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.remove_circle_outline_rounded,
                                      color: !_isGive ? kRed : kTextSecondary,
                                      size: 20),
                                  const SizedBox(width: 8),
                                  Text('Quitar',
                                      style: TextStyle(
                                          color: !_isGive ? kRed : kTextSecondary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              AnimatedEntry(
                delay: const Duration(milliseconds: 350),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ICONO',
                        style: TextStyle(
                            color: kTextSecondary,
                            fontSize: 11,
                            letterSpacing: 2)),
                    const SizedBox(height: 8),
                    _buildIconGrid(),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              AnimatedEntry(
                delay: const Duration(milliseconds: 450),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Guardar',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconGrid() {
    final entries = BankSettingsService.availableIcons.entries.toList();
    final itemsPerRow = 6;
    final rows = <List<MapEntry<String, IconData>>>[];
    for (var i = 0; i < entries.length; i += itemsPerRow) {
      rows.add(entries.sublist(i, min(i + itemsPerRow, entries.length)));
    }
    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: row.map((entry) {
              final selected = entry.key == _selectedIcon;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedIcon = entry.key),
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
                        color: selected ? kGold : kTextSecondary, size: 22),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}
