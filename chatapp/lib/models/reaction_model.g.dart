// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reaction_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReactionAdapter extends TypeAdapter<Reaction> {
  @override
  final int typeId = 2;

  @override
  Reaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Reaction(
      emoji: fields[0] as String,
      userId: fields[1] as String,
      userName: fields[2] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Reaction obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.emoji)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.userName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReactionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
