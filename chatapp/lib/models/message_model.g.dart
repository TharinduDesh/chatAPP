// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MessageAdapter extends TypeAdapter<Message> {
  @override
  final int typeId = 1;

  @override
  Message read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Message(
      id: fields[0] as String,
      conversationId: fields[1] as String,
      sender: fields[2] as User?,
      content: fields[3] as String,
      fileUrl: fields[4] as String?,
      fileType: fields[5] as String?,
      fileName: fields[6] as String?,
      replyTo: fields[7] as String?,
      replySnippet: fields[8] as String?,
      replySenderName: fields[9] as String?,
      reactions: (fields[10] as List).cast<Reaction>(),
      createdAt: fields[11] as DateTime,
      deletedAt: fields[12] as DateTime?,
      isEdited: fields[13] as bool,
      messageType: fields[14] as String,
      status: fields[15] as String,
      isEncrypted: fields[16] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Message obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.conversationId)
      ..writeByte(2)
      ..write(obj.sender)
      ..writeByte(3)
      ..write(obj.content)
      ..writeByte(4)
      ..write(obj.fileUrl)
      ..writeByte(5)
      ..write(obj.fileType)
      ..writeByte(6)
      ..write(obj.fileName)
      ..writeByte(7)
      ..write(obj.replyTo)
      ..writeByte(8)
      ..write(obj.replySnippet)
      ..writeByte(9)
      ..write(obj.replySenderName)
      ..writeByte(10)
      ..write(obj.reactions)
      ..writeByte(11)
      ..write(obj.createdAt)
      ..writeByte(12)
      ..write(obj.deletedAt)
      ..writeByte(13)
      ..write(obj.isEdited)
      ..writeByte(14)
      ..write(obj.messageType)
      ..writeByte(15)
      ..write(obj.status)
      ..writeByte(16)
      ..write(obj.isEncrypted);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
