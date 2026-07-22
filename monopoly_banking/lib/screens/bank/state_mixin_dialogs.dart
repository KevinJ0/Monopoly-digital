part of '../bank_screen.dart';

mixin _BankDialogs on State<BankScreen> {
  _BankScreenState get _self => this as _BankScreenState;

  void _toast(String msg, Color color) {
    NotificationService().show(msg, backgroundColor: color);
  }

  Future<void> _failOperationDialog(
    _BankOperationDialogController dialog,
    String title,
    String message, {
    IconData icon = Icons.close_rounded,
    Color color = kRed,
  }) async {
    dialog.fail(title: title, message: message, icon: icon, color: color);
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  Future<bool?> _confirmBankruptcy({
    required String playerId,
    required double availableBalance,
    required double chargeAmount,
  }) {
    return showGameDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kBgCard,
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: kRed,
          size: 54,
        ),
        title: const Text(
          'Riesgo de bancarrota',
          textAlign: TextAlign.center,
        ),
        content: Text(
          '$playerId dispone de ${formatMoney(availableBalance)}, pero el cobro es de ${formatMoney(chargeAmount)}. '
          'Si continúas, el jugador perderá la partida y este dispositivo quedará bloqueado hasta que cierres la sesión del banco.\n\n'
          '¿Deseas declarar al jugador en bancarrota?',
          textAlign: TextAlign.center,
          style: const TextStyle(color: kTextSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kRed,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.gavel_rounded),
            label: const Text('Declarar bancarrota'),
          ),
        ],
      ),
    );
  }

  Future<void> _showOperationDialog(_BankOperationDialogController controller) {
    return showGameDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var autoCloseScheduled = false;

        return PopScope(
          canPop: false,
          child: ValueListenableBuilder<String>(
            valueListenable: controller.title,
            builder: (context, title, _) {
              return ValueListenableBuilder<String>(
                valueListenable: controller.message,
                builder: (context, message, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: controller.completed,
                    builder: (context, completed, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: controller.failed,
                        builder: (context, failed, _) {
                          final finished = completed || failed;
                          if (finished && !autoCloseScheduled) {
                            autoCloseScheduled = true;
                            Future.delayed(
                              Duration(seconds: completed ? 3 : 2),
                              () {
                                if (ctx.mounted && Navigator.of(ctx).canPop()) {
                                  Navigator.of(ctx).pop();
                                }
                              },
                            );
                          }

                          return AlertDialog(
                            insetPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 24,
                            ),
                            contentPadding:
                                const EdgeInsets.fromLTRB(16, 14, 16, 10),
                            backgroundColor: kBgCard,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                              side: BorderSide(
                                color: completed
                                    ? kGreen.withValues(alpha: 0.45)
                                    : failed
                                        ? controller.failedColor
                                            .withValues(alpha: 0.45)
                                        : Colors.blue
                                            .withValues(alpha: 0.35),
                              ),
                            ),
                            title: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 340),
                              child: Center(
                                child: Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: const TextStyle(
                                    color: kTextPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            content: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: 340,
                                maxHeight:
                                    MediaQuery.sizeOf(context).height * 0.55,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 136,
                                    height: 136,
                                    child: Center(
                                      child: _OperationLoadingVisual(
                                        completed: completed,
                                        failed: failed,
                                        transportType: controller.transportType,
                                        failedIcon: controller.failedIcon,
                                        failedColor: controller.failedColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Flexible(
                                    child: SingleChildScrollView(
                                      child: Center(
                                        child: AnimatedSwitcher(
                                          duration:
                                              const Duration(milliseconds: 220),
                                          child: Text(
                                            message,
                                            key: ValueKey(message),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: kTextSecondary,
                                              height: 1.35,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (kDebugMode) ...[
                                    const SizedBox(height: 10),
                                    ValueListenableBuilder<String>(
                                      valueListenable: controller.debugInfo,
                                      builder: (context, debugInfo, _) {
                                        if (debugInfo.isEmpty) {
                                          return const SizedBox.shrink();
                                        }
                                        return Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.4),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            debugInfo,
                                            style: const TextStyle(
                                              color: Colors.greenAccent,
                                              fontSize: 10,
                                              fontFamily: 'monospace',
                                              height: 1.4,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            actions: [
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: finished
                                    ? ElevatedButton(
                                        onPressed: () {
                                          SoundService.playClick();
                                          Navigator.of(ctx).pop();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: completed
                                              ? kGreen
                                              : controller.failedColor,
                                          foregroundColor: Colors.black,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: const Text(
                                          'Cerrar',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: () {
                                          SoundService.playClick();
                                          controller.cancelled.value = true;
                                          Navigator.of(ctx).pop();
                                        },
                                        child: const Text('Cancelar'),
                                      ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      if (!controller.completed.value && !controller.failed.value) {
        controller.cancelled.value = true;
      }
    });
  }


  Future<void> _send() async {
    SoundService.playClick();
    if (!_self._formKey.currentState!.validate()) return;
    AppAuditLogger.instance.event('BANK_OP', '_send start',
        data: {'op': _self._selectedOp, 'amount': _self._amountCtrl.text});

    final connectedPlayers = P2PService()
        .wsTransport
        .connectedPlayersNotifier
        .value
        .where((p) => p.connected && p.name.isNotEmpty)
        .toList();
    if (connectedPlayers.isEmpty) {
      if (mounted) {
        NotificationService().show(
          'No hay jugadores conectados',
          backgroundColor: Colors.orange,
        );
      }
      setState(() => _self._sending = false);
      return;
    }

    final targetPlayer = await _self._selectTargetPlayer(
      title: 'Seleccionar jugador',
    );
    if (targetPlayer == null) {
      setState(() => _self._sending = false);
      return;
    }

    setState(() => _self._sending = true);
    final dialog = _BankOperationDialogController(
      transportType: P2PService().currentType,
    );
    var dialogOpen = false;

    dialogOpen = true;
    _showOperationDialog(dialog).whenComplete(() {
      dialogOpen = false;
    });
    await Future<void>.delayed(Duration.zero);

    try {
      dialog.update(
        title: _self._operationWaitTitle(),
        message: _self._operationWaitMessage(),
      );

      final ledger = BankLedgerService();
      final playerId = targetPlayer.displayName;

      if (_self._selectedOp == 'passGo') {
        final passGoAmount = BankSettingsService().passGoAmount;
        final result = await ledger.passGo(playerId);
          await _self._sendToConnectedPlayer(result.toClientPayload());
          SoundService.playFanfare();
          HapticFeedback.vibrate();
          NotificationService().show(
              '$playerId pasó por GO: +${formatMoney(passGoAmount)}',
              backgroundColor: kGold);
      } else if (_self._selectedOp.startsWith('custom:')) {
        final fixedAmount = _self._fixedAmountForSelectedOp();
        if (fixedAmount <= 0) {
          throw const BankLedgerException('Monto inválido para la operación personalizada.');
        }
        final customId = _self._selectedOp.substring('custom:'.length);
        final opName = BankSettingsService()
            .customOps
            .where((c) => c.id == customId)
            .firstOrNull
            ?.name;
        final isGive = BankSettingsService()
            .customOps
            .where((c) => c.id == customId)
            .firstOrNull
            ?.isGive ?? true;
        if (isGive) {
          final result = await ledger.credit(
            playerId,
            fixedAmount,
            type: 'custom_$customId',
          );
          final payload = result.toClientPayload();
          if (opName != null) payload['customOpName'] = opName;
          await _self._sendToConnectedPlayer(payload);
          SoundService.playSuccess();
          HapticFeedback.mediumImpact();
          NotificationService().show(
              '${opName ?? 'Operación'}: +${formatMoney(fixedAmount)} a $playerId',
              backgroundColor: Colors.green.shade700);
        } else {
          final account = ledger.accountFor(playerId);
          if (account == null) {
            throw const BankLedgerException(
              'El jugador necesita completar el handshake inicial.',
            );
          }
          if (fixedAmount > account.balance) {
            final proceed = await _confirmBankruptcy(
              playerId: playerId,
              availableBalance: account.balance,
              chargeAmount: fixedAmount,
            );
            if (proceed != true) {
              await _failOperationDialog(
                dialog,
                'Operación cancelada',
                'El jugador conserva su saldo y continúa activo en la partida.',
                icon: Icons.shield_outlined,
                color: Colors.orange,
              );
              return;
            }
            final result = await ledger.markBankrupt(
              playerId,
              attemptedCharge: fixedAmount,
              deviceInstallationId: targetPlayer.deviceInstallationId,
            );
            await _self._sendToConnectedPlayer(result.toClientPayload());
            SoundService.playSadTrombone();
            HapticFeedback.heavyImpact();
            NotificationService().show(
                '$playerId en bancarrota. Expulsado de la partida.',
                backgroundColor: kRed);
            dialog.complete(
              '$playerId fue declarado en bancarrota y expulsado de la partida.',
            );
            return;
          }
          final result = await ledger.debit(
            playerId,
            fixedAmount,
            type: 'custom_$customId',
          );
          final payload = result.toClientPayload();
          if (opName != null) payload['customOpName'] = opName;
          await _self._sendToConnectedPlayer(payload);
          SoundService.playSadTrombone();
          HapticFeedback.heavyImpact();
          NotificationService().show(
              '${opName ?? 'Operación'}: -${formatMoney(fixedAmount)} a $playerId',
              backgroundColor: Colors.orange.shade800);
        }
      } else {
        final amount = double.parse(_self._amountCtrl.text.replaceAll(',', ''));
        if (_self._selectedOp == 'receive') {
          final result = await ledger.credit(
            playerId,
            amount,
            type: 'payment',
            counterpartyId: 'Banco',
          );
          await _self._sendToConnectedPlayer(result.toClientPayload());
          SoundService.playSuccess();
          HapticFeedback.mediumImpact();
          NotificationService().show(
              'Pagado ${formatMoney(amount)} a $playerId',
              backgroundColor: Colors.green.shade700);
        } else {
          final account = ledger.accountFor(playerId);
          if (account == null) {
            throw const BankLedgerException(
              'El jugador necesita completar el handshake inicial.',
            );
          }
          if (amount > account.balance) {
            final proceed = await _confirmBankruptcy(
              playerId: playerId,
              availableBalance: account.balance,
              chargeAmount: amount,
            );
            if (proceed != true) {
              await _failOperationDialog(
                dialog,
                'Cobro cancelado',
                'El jugador conserva su saldo y continúa activo en la partida.',
                icon: Icons.shield_outlined,
                color: Colors.orange,
              );
              return;
            }

            final result = await ledger.markBankrupt(
              playerId,
              attemptedCharge: amount,
              deviceInstallationId: targetPlayer.deviceInstallationId,
            );
            await _self._sendToConnectedPlayer(result.toClientPayload());
            SoundService.playSadTrombone();
            HapticFeedback.heavyImpact();
            NotificationService().show(
                '$playerId en bancarrota. Expulsado de la partida.',
                backgroundColor: kRed);
            dialog.complete(
              '$playerId fue declarado en bancarrota y expulsado de la partida.',
            );
            return;
          }
          final result = await ledger.debit(
            playerId,
            amount,
            type: 'charge',
            counterpartyId: 'Banco',
          );
          await _self._sendToConnectedPlayer(result.toClientPayload());
          SoundService.playSadTrombone();
          HapticFeedback.heavyImpact();
          NotificationService().show(
              'Cobrado ${formatMoney(amount)} a $playerId',
              backgroundColor: Colors.orange.shade800);
        }
      }
      dialog
          .complete('Proceso completado con el jugador $playerId');
    } catch (e, s) {
      AppAuditLogger.instance.event('BANK_OP', '_send_error',
          data: {'op': _self._selectedOp, 'error': e.toString()},
          error: e,
          stack: s);
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        if (e is TransportUnavailableException) {
          _toast(e.transportName, kRed);
        } else {
          context.showFriendlyError(e, s);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _self._sending = false);
        _self._amountCtrl.clear();
      }
    }
  }

  Future<void> _handleTransferHoldRequest(Map<String, dynamic> payload) async {
    if (_self._transferHoldDialogOpen || !mounted) return;

    final rawAmount = payload['amount'] as num?;
    final amount = rawAmount?.toDouble() ?? 0;
    if (amount <= 0 || !amount.isFinite) return;

    final fromName = ((payload['fromPlayerId'] as String?) ??
            (payload['fromName'] as String?) ??
            'Jugador')
        .trim();

    _self._transferHoldDialogOpen = true;
    await showGameDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var delivering = false;
        var completed = false;
        var status =
            'Selecciona el jugador que recibirá el dinero y pulsa entregar.';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> deliver() async {
              if (delivering || completed) return;
              setDialogState(() {
                delivering = true;
                status = 'Seleccionando jugador receptor...';
              });

              final receiver = await _self._selectTransferReceiver(
                excludePlayerId: fromName,
              );
              if (receiver == null) {
                if (!ctx.mounted) return;
                setDialogState(() {
                  delivering = false;
                  status =
                      'No hay jugadores disponibles. Conecta al receptor e intenta de nuevo.';
                });
                return;
              }

              try {
                P2PService().setTransport(TransportType.ws);
                await P2PService().sendPayload({
                  'type': 'payment',
                  'amount': amount,
                  'targetPlayerId': receiver.displayName,
                  'targetInstallationId': receiver.deviceInstallationId,
                  'transferFrom': fromName,
                });
                if (!ctx.mounted) return;
                setDialogState(() {
                  delivering = false;
                  completed = true;
                  status =
                      'Proceso completado con el jugador ${receiver.displayName}.';
                });
                Future.delayed(const Duration(seconds: 3), () {
                  if (ctx.mounted && Navigator.of(ctx).canPop()) {
                    Navigator.of(ctx).pop();
                  }
                });
              } catch (e, s) {
                if (!mounted || !ctx.mounted) return;
                context.showFriendlyError(e, s);
                setDialogState(() {
                  delivering = false;
                  status = 'No pude entregar el dinero. Intenta de nuevo.';
                });
              }
            }

            return AlertDialog(
              backgroundColor: kBgCard,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: completed
                      ? kGreen.withValues(alpha: 0.45)
                      : kGold.withValues(alpha: 0.35),
                ),
              ),
              title: Text(
                completed ? 'Transferencia completada' : 'Dinero retenido',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 300,
                height: 226,
                child: Column(
                  children: [
                    Icon(
                      completed
                          ? Icons.check_circle_rounded
                          : Icons.account_balance_wallet_rounded,
                      color: completed ? kGreen : kGold,
                      size: 72,
                    ),
                    Text(
                      formatMoney(amount),
                      style: const TextStyle(
                        color: kGold,
                        fontWeight: FontWeight.w900,
                        fontSize: 30,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'De: ${fromName.isEmpty ? 'Jugador' : fromName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Center(
                        child: Text(
                          status,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: kTextSecondary,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (!completed)
                  TextButton(
                    onPressed: () {
                      SoundService.playClick();
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Cerrar'),
                  ),
                SizedBox(
                  width: completed ? double.infinity : 150,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: completed || delivering ? null : deliver,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: completed ? kGreen : kGold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: delivering
                        ? const AppSpinner(
                            size: 18,
                            color: Colors.black,
                          )
                        : Icon(completed
                            ? Icons.check_rounded
                            : Icons.touch_app_rounded),
                    label: Text(
                      completed ? 'Completado' : 'Entregar',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                ),
              ),
              ],
              );
            },
          );
        },
    );
  }

  void _showPlayerDetailDialog(
    WsPlayer player,
    BankPlayerAccount? account,
  ) {
    final ledger = BankLedgerService();
    final transactions = ledger.transactionHistory
        .where((tx) => tx['playerId'] == player.displayName)
        .toList();
    final volume = transactions.fold<double>(
      0,
      (sum, tx) => sum + (((tx['amount'] as num?)?.toDouble() ?? 0).abs()),
    );
    final passGoCount =
        transactions.where((tx) => tx['type'] == 'passGo').length;
    final txCount = transactions.length;
    final balance = account?.balance ?? 0;
    final playerColor = _self._playerColor(player.colorId);
    final avatar = player.avatarId.isNotEmpty
        ? player.avatarId
        : '\u{1F464}';
    final tier = _self._playerTier(balance);
    final tierLabel = _self._tierLabel(tier);
    final tierColor = _self._tierColor(tier);

    showGameDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kBgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: DefaultTabController(
          length: 2,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: playerColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            avatar,
                            style: TextStyle(
                              fontSize: 20,
                              color: playerColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          player.displayName,
                          style: const TextStyle(
                            color: kTextPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TabBar(
                    labelColor: kGold,
                    unselectedLabelColor: kTextSecondary,
                    indicatorColor: kGold,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    tabs: const [
                      Tab(text: 'Datos Jugador'),
                      Tab(text: 'Datos Conexion'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        PlayerInfoView(
                          player: player,
                          balance: balance,
                          volume: volume,
                          passGoCount: passGoCount,
                          txCount: txCount,
                          tier: tier,
                          tierLabel: tierLabel,
                          tierColor: tierColor,
                          transactions: transactions,
                        ),
                        _self._buildConnectionInfoTab(player),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                      onPressed: () async {
                        final confirm = await _confirmKick(
                          context,
                          player.displayName,
                        );
                        if (confirm != true || !ctx.mounted) return;
                        Navigator.pop(ctx);
                        try {
                          final installationId = player.deviceInstallationId;
                          if (installationId.isNotEmpty) {
                            await BankLedgerService()
                                .banDevice(installationId, player.displayName);
                          }
                          await P2PService().sendPayload({
                            'type': 'kick',
                            'targetPlayerId': player.displayName,
                            'targetInstallationId': installationId,
                            'playerId': player.displayName,
                          });
                        } on TransportUnavailableException {
                          // El jugador ya se desconectó — fue expulsado igual.
                        }
                      },
                      icon: const Icon(Icons.gavel_rounded, size: 18),
                      label: const Text(
                        'Sacar del juego',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmKick(
    BuildContext outerContext,
    String playerName,
  ) {
    return showGameDialog<bool>(
      context: outerContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Expulsar jugador',
            style: TextStyle(color: kTextPrimary)),
        content: Text(
          '¿Estás seguro de que deseas expulsar a "$playerName" de la partida? No podrá reconectarse hasta que inicies una nueva sesión.',
          style: const TextStyle(color: kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Expulsar',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
