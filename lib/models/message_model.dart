import 'package:hive/hive.dart';

part 'message_model.g.dart';

@HiveType(typeId: 0)
class MessageModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String content;

  @HiveField(2)
  final String senderId;

  @HiveField(3)
  final String receiverId;

  @HiveField(4)
  final DateTime timestamp;

  @HiveField(5)
  final MessageStatus status;

  @HiveField(6)
  final bool isSent;

  MessageModel({
    required this.id,
    required this.content,
    required this.senderId,
    required this.receiverId,
    required this.timestamp,
    this.status = MessageStatus.sending,
    required this.isSent,
  });

  MessageModel copyWith({
    String? id,
    String? content,
    String? senderId,
    String? receiverId,
    DateTime? timestamp,
    MessageStatus? status,
    bool? isSent,
  }) {
    return MessageModel(
      id: id ?? this.id,
      content: content ?? this.content,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      isSent: isSent ?? this.isSent,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'senderId': senderId,
      'receiverId': receiverId,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
      'isSent': isSent,
    };
  }

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as String,
      content: json['content'] as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MessageStatus.sent,
      ),
      isSent: json['isSent'] as bool? ?? true,
    );
  }

  @override
  String toString() {
    return 'MessageModel(id: $id, content: $content, senderId: $senderId, receiverId: $receiverId, timestamp: $timestamp, status: $status, isSent: $isSent)';
  }
}

@HiveType(typeId: 1)
enum MessageStatus {
  @HiveField(0)
  sending,
  @HiveField(1)
  sent,
  @HiveField(2)
  delivered,
  @HiveField(3)
  failed,
}




