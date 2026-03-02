import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:monopoly_banking/core/constants.dart';
import 'package:monopoly_banking/providers/session_provider.dart';
import 'package:monopoly_banking/providers/wallet_controller.dart';
import 'package:monopoly_banking/services/p2p_service.dart';
import 'package:monopoly_banking/services/network_service.dart';

class BankScreen extends StatefulWidget {
  const BankScreen({super.key});

  @override
  State<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<BankScreen> with SingleTickerProviderStateMixin {
  final _amountCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;
  String _selectedOp = 'payment';
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slide;

  final _operations = const [
    _OpOption(id: 'payment', label: 'Cobrar al jugador', icon: Icons.arrow_upward_rounded, color: kRed),
    _OpOption(id: 'receive', label: 'Pagar al jugador', icon: Icons.arrow_downward_rounded, color: kGreen),
    _OpOption(id: 'handshake', label: 'Handshake inicial', icon: Icons.wifi_tethering_rounded, color: kGold),
    _OpOption(id: 'passGo', label: 'Pasar por GO', icon: Icons.flag_rounded, color: kGold),
    _OpOption(id: 'manual', label: 'Intermediario Físico', icon: Icons.handshake_rounded, color: Colors.cyan),
  ];

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    P2PService().payloadStream.listen((payload) {
      if (!mounted) return;
      if (payload['type'] == 'handshake_confirm') {
        final name = payload['name'] as String? ?? 'Jugador';
        _toast('✅ $name se ha unido a la partida', kGold);
      }
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _sending = true);

    try {
      if (_selectedOp == 'handshake') {
        final amountText = _amountCtrl.text.isEmpty ? '2000' : _amountCtrl.text.replaceAll(',', '');
        final amount = double.parse(amountText);
        final session = context.read<SessionProvider>();
        await P2PService().sendHandshake(
          initialBalance: amount,
          avatarId: session.avatarId,
          colorId: session.colorId,
          gameId: 'monopoly',
          name: session.name,
        );
        _toast('Handshake enviado con \$$amount', kGold);
      } else if (_selectedOp == 'passGo') {
        await P2PService().sendPayload({'type': 'passGo'});
        _toast('Pass GO enviado (+\$${kPassGoAmount.round()})', kGold);
      } else {
        final amount = double.parse(_amountCtrl.text.replaceAll(',', ''));
        if (_selectedOp == 'receive') {
          final wallet = context.read<WalletController>();
          await wallet.subtractFunds(amount);
          await P2PService().sendPayload({'type': 'payment', 'amount': amount});
          _toast('Pago de \$$amount enviado', kGreen);
        } else {
          await P2PService().sendPayload({'type': 'charge', 'amount': amount});
          _toast('Cobro de \$$amount solicitado', kRed);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _amountCtrl.clear();
      }
    }
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: kBgDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kTextSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Panel del Banco',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _slideCtrl,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 28),
                  _buildOpSelector(),
                  const SizedBox(height: 24),
                  if (_selectedOp == 'manual')
                    _buildManualTransferInterface()
                  else ...[
                    if (_selectedOp != 'passGo') _buildAmountField(),
                    const SizedBox(height: 28),
                    _buildQuickAmounts(),
                    const SizedBox(height: 32),
                    _buildSendButton(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManualTransferInterface() {
    return StreamBuilder<TransferState>(
      stream: BancoServer().stateStream,
      initialData: BancoServer().state,
      builder: (context, snapshot) {
        final state = snapshot.data!;
        return Container(
          padding: const EdgeInsets.all(24),
          width: double.infinity,
          decoration: BoxDecoration(
            color: kBgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBorder),
          ),
          child: Column(
            children: [
              _buildStateAnimation(state),
              const SizedBox(height: 24),
              Text(
                _getStateLabel(state),
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _getStateSublabel(state),
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextSecondary, fontSize: 14),
              ),
              if (state == TransferState.idle) ...[
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => BancoServer().start(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Iniciar Servidor de Banco', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStateAnimation(TransferState state) {
    if (state == TransferState.idle) {
      return const Icon(Icons.power_settings_new_rounded, size: 80, color: kBorder);
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: CircularProgressIndicator(
            value: state == TransferState.holding ? 1.0 : null,
            strokeWidth: 8,
            color: _getStateColor(state),
          ),
        ),
        Icon(_getStateIcon(state), size: 40, color: _getStateColor(state)),
      ],
    );
  }

  String _getStateLabel(TransferState state) {
    switch (state) {
      case TransferState.idle:
        return 'Servidor de Banco Apagado';
      case TransferState.listening:
        return 'Banco Activo';
      case TransferState.waitingSender:
        return 'Esperando Emisor';
      case TransferState.holding:
        return 'Dinero Retenido';
      case TransferState.waitingReceiver:
        return 'Esperando Receptor';
    }
  }

  String _getStateSublabel(TransferState state) {
    switch (state) {
      case TransferState.idle:
        return 'Inicia el servidor para transacciones manuales';
      case TransferState.listening:
        return 'Esperando transferencia de un jugador...';
      case TransferState.waitingSender:
        return 'El emisor debe acercar el dispositivo';
      case TransferState.holding:
        return 'Validando saldo y procesando débito...';
      case TransferState.waitingReceiver:
        return 'Retención completa. Receptor acerque dispositivo';
    }
  }

  Color _getStateColor(TransferState state) {
    switch (state) {
      case TransferState.listening:
        return Colors.cyan;
      case TransferState.waitingSender:
        return kRed;
      case TransferState.holding:
        return kGold;
      case TransferState.waitingReceiver:
        return kGreen;
      default:
        return kBorder;
    }
  }

  IconData _getStateIcon(TransferState state) {
    switch (state) {
      case TransferState.listening:
        return Icons.sensors_rounded;
      case TransferState.waitingSender:
        return Icons.upload_rounded;
      case TransferState.holding:
        return Icons.lock_clock_rounded;
      case TransferState.waitingReceiver:
        return Icons.download_rounded;
      default:
        return Icons.error;
    }
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kGold.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_balance_rounded, color: kGold, size: 28),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Banca Central',
                style: TextStyle(color: kGold, fontWeight: FontWeight.w800, fontSize: 16),
              ),
              Text(
                'Gestiona el capital de los jugadores',
                style: TextStyle(color: kTextSecondary, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOpSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'OPERACIÓN',
          style: TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2),
        ),
        const SizedBox(height: 12),
        ...(_operations.map((op) => _buildOpTile(op))),
      ],
    );
  }

  Widget _buildOpTile(_OpOption op) {
    final selected = _selectedOp == op.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedOp = op.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? op.color.withValues(alpha: 0.12) : kBgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? op.color : kBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(op.icon, color: selected ? op.color : kTextSecondary, size: 20),
            const SizedBox(width: 12),
            Text(
              op.label,
              style: TextStyle(
                color: selected ? op.color : kTextSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (selected)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: op.color,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MONTO',
          style: TextStyle(color: kTextSecondary, fontSize: 11, letterSpacing: 2),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _amountCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: kTextPrimary, fontSize: 24, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            prefixText: '\$ ',
            prefixStyle: const TextStyle(color: kGreen, fontSize: 24, fontWeight: FontWeight.w700),
            hintText: '0',
            hintStyle: const TextStyle(color: kBorder, fontSize: 24),
            filled: true,
            fillColor: kBgCard,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kGreen, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kRed),
            ),
          ),
          validator: (v) {
            if (_selectedOp == 'handshake' && (v == null || v.isEmpty)) return null;
            if (v == null || v.isEmpty) return 'Ingresa un monto';
            final n = double.tryParse(v);
            if (n == null || n <= 0) return 'Monto inválido';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildQuickAmounts() {
    if (_selectedOp == 'handshake' || _selectedOp == 'passGo') return const SizedBox();
    const presets = [50, 100, 200, 500, 1000, 2000];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presets.map((p) {
        return GestureDetector(
          onTap: () => _amountCtrl.text = '$p',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBorder),
            ),
            child: Text(
              '\$$p',
              style: const TextStyle(color: kTextSecondary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSendButton() {
    final op = _operations.firstWhere((o) => o.id == _selectedOp);
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: ElevatedButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : Icon(op.icon),
          label: Text(
            _sending ? 'Enviando...' : op.label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: op.color,
            foregroundColor: op.color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
        ),
      ),
    );
  }
}

class _OpOption {
  final String id;
  final String label;
  final IconData icon;
  final Color color;

  const _OpOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });
}
