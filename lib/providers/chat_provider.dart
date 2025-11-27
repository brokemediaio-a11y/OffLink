import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/message_model.dart';
import '../services/storage/message_storage.dart';
import '../providers/connection_provider.dart';
import '../utils/logger.dart';

class ChatState {
  final List<MessageModel> messages;
  final bool isSending;
  final String? error;
  final String currentDeviceId;

  ChatState({
    this.messages = const [],
    this.isSending = false,
    this.error,
    required this.currentDeviceId,
  });

  ChatState copyWith({
    List<MessageModel>? messages,
    bool? isSending,
    String? error,
    String? currentDeviceId,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      error: error ?? this.error,
      currentDeviceId: currentDeviceId ?? this.currentDeviceId,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final ConnectionNotifier _connectionNotifier;
  final String _currentDeviceId;
  StreamSubscription<String>? _messageSubscription;

  ChatNotifier(ConnectionNotifier connectionNotifier, String currentDeviceId)
      : _connectionNotifier = connectionNotifier,
        _currentDeviceId = currentDeviceId,
        super(ChatState(currentDeviceId: currentDeviceId)) {
    _loadMessages();
    _setupMessageListener();
  }

  void _setupMessageListener() {
    // Listen to incoming messages from connection manager
    // Note: This would need to be set up through the connection manager
    // For now, we'll handle messages when they arrive
  }

  Future<void> _loadMessages() async {
    try {
      final allMessages = MessageStorage.getAllMessages();
      // Filter messages for current conversation
      // For now, we'll load all messages
      state = state.copyWith(messages: allMessages);
      Logger.info('Loaded ${allMessages.length} messages');
    } catch (e) {
      Logger.error('Error loading messages', e);
      state = state.copyWith(error: 'Failed to load messages');
    }
  }

  Future<void> sendMessage(String content, String receiverId) async {
    if (content.trim().isEmpty) return;

    try {
      final message = MessageModel(
        id: const Uuid().v4(),
        content: content.trim(),
        senderId: _currentDeviceId,
        receiverId: receiverId,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        isSent: true,
      );

      // Add message to state immediately
      state = state.copyWith(
        messages: [...state.messages, message],
        isSending: true,
        error: null,
      );

      // Save to local storage
      await MessageStorage.saveMessage(message);

      // Send via connection manager
      final messageJson = message.toJson();
      final sent = await _connectionNotifier.sendMessage(
        messageJson.toString(),
      );

      if (sent) {
        // Update message status to sent
        await MessageStorage.updateMessageStatus(
          message.id,
          MessageStatus.sent,
        );
        
        final updatedMessages = state.messages.map((m) {
          if (m.id == message.id) {
            return m.copyWith(status: MessageStatus.sent);
          }
          return m;
        }).toList();

        state = state.copyWith(
          messages: updatedMessages,
          isSending: false,
        );
        Logger.info('Message sent successfully');
      } else {
        // Update message status to failed
        await MessageStorage.updateMessageStatus(
          message.id,
          MessageStatus.failed,
        );
        
        final updatedMessages = state.messages.map((m) {
          if (m.id == message.id) {
            return m.copyWith(status: MessageStatus.failed);
          }
          return m;
        }).toList();

        state = state.copyWith(
          messages: updatedMessages,
          isSending: false,
          error: 'Failed to send message',
        );
        Logger.error('Failed to send message');
      }
    } catch (e) {
      Logger.error('Error sending message', e);
      state = state.copyWith(
        isSending: false,
        error: 'Error sending message: ${e.toString()}',
      );
    }
  }

  void receiveMessage(String messageJson) {
    try {
      // Parse message JSON
      // For now, we'll create a simple message
      final message = MessageModel(
        id: const Uuid().v4(),
        content: messageJson, // Simplified - should parse JSON
        senderId: 'other', // Should extract from JSON
        receiverId: _currentDeviceId,
        timestamp: DateTime.now(),
        status: MessageStatus.delivered,
        isSent: false,
      );

      // Add to state
      state = state.copyWith(
        messages: [...state.messages, message],
      );

      // Save to local storage
      MessageStorage.saveMessage(message);
      Logger.info('Message received and saved');
    } catch (e) {
      Logger.error('Error receiving message', e);
    }
  }

  Future<void> loadMessagesForConversation(String otherDeviceId) async {
    try {
      final messages = MessageStorage.getMessagesForConversation(otherDeviceId);
      state = state.copyWith(messages: messages);
      Logger.info('Loaded messages for conversation: $otherDeviceId');
    } catch (e) {
      Logger.error('Error loading conversation messages', e);
      state = state.copyWith(error: 'Failed to load messages');
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }
}

// Provider for current device ID (should be generated once per app install)
final currentDeviceIdProvider = Provider<String>((ref) {
  // In a real app, this would be stored and retrieved from local storage
  return const Uuid().v4();
});

// Provider for ChatNotifier
final chatProvider = StateNotifierProvider.family<ChatNotifier, ChatState, String>((ref, receiverId) {
  final connectionNotifier = ref.watch(connectionProvider.notifier);
  final currentDeviceId = ref.watch(currentDeviceIdProvider);
  return ChatNotifier(connectionNotifier, currentDeviceId);
});

