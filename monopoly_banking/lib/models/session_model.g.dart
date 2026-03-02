// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SessionModelAdapter extends TypeAdapter<SessionModel> {
  @override
  final int typeId = 1;

  @override
  SessionModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SessionModel(
      role: fields[0] as String,
      balance: fields[1] as double,
      avatarId: fields[2] as String,
      colorId: fields[3] as String,
      totalVolume: fields[5] as double,
      txCount: fields[6] as int,
      passGoCount: fields[7] as int,
      isBankrupt: fields[4] as bool,
      name: fields[8] as String?,
      isHandshakeDone: fields[9] as bool,
      vaultInvestedAmount: fields[10] as double,
      vaultGeneratedAmount: fields[12] as double,
      vaultTargetPasses: fields[13] as int,
      vaultCurrentPasses: fields[14] as int,
      balanceHistory: (fields[11] as List?)?.cast<double>(),
    );
  }

  @override
  void write(BinaryWriter writer, SessionModel obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.role)
      ..writeByte(1)
      ..write(obj.balance)
      ..writeByte(2)
      ..write(obj.avatarId)
      ..writeByte(3)
      ..write(obj.colorId)
      ..writeByte(4)
      ..write(obj.isBankrupt)
      ..writeByte(5)
      ..write(obj.totalVolume)
      ..writeByte(6)
      ..write(obj.txCount)
      ..writeByte(7)
      ..write(obj.passGoCount)
      ..writeByte(8)
      ..write(obj.name)
      ..writeByte(9)
      ..write(obj.isHandshakeDone)
      ..writeByte(10)
      ..write(obj.vaultInvestedAmount)
      ..writeByte(11)
      ..write(obj.balanceHistory)
      ..writeByte(12)
      ..write(obj.vaultGeneratedAmount)
      ..writeByte(13)
      ..write(obj.vaultTargetPasses)
      ..writeByte(14)
      ..write(obj.vaultCurrentPasses);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
