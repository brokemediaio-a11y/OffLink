import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../services/storage/message_storage.dart';
import '../services/storage/device_storage.dart';
import '../utils/logger.dart';

class ConversationsState {
  final List<ConversationModel> conversations;
  final bool isLoading;

  ConversationsState({
    this.conversations = const [],
    this.isLoading = false,
  });

  ConversationsState copyWith({
    List<ConversationModel>? conversations,
    bool? isLoading,
  }) {
    return ConversationsState(
      conversations: conversations ?? this.conversations,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ConversationsNotifier extends StateNotifier<ConversationsState> {
  ConversationsNotifier() : super(ConversationsState()) {
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    state = state.copyWith(isLoading: true);
    try {
      final allMessages = MessageStorage.getAllMessages();
      
      // Group messages by device (conversation partner)
      final Map<String, List<MessageModel>> messagesByDevice = {};
      
      for (final message in allMessages) {
        // Determine the other device ID
        final otherDeviceId = message.isSent ? message.receiverId : message.senderId;
        
        if (!messagesByDevice.containsKey(otherDeviceId)) {
          messagesByDevice[otherDeviceId] = [];
        }
        messagesByDevice[otherDeviceId]!.add(message);
      }
      
      // Create conversation models
      final List<ConversationModel> conversations = [];
      
      for (final entry in messagesByDevice.entries) {
        final deviceId = entry.key;
        final messages = entry.value;
        
        // Sort messages by timestamp
        messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        final lastMessage = messages.first;
        
        // Count unread messages (messages not sent by us)
        final unreadCount = messages.where((m) => !m.isSent).length;
        
        // Try to get stored device name, fallback to deviceId
        final storedName = DeviceStorage.getDeviceDisplayName(deviceId);
        final displayName = storedName ?? deviceId;
        
        conversations.add(ConversationModel(
          deviceId: deviceId,
          deviceName: displayName, // Use stored name or deviceId
          lastMessage: lastMessage.content,
          lastMessageTime: lastMessage.timestamp,
          unreadCount: unreadCount,
          isConnected: false, // Will be updated based on connection state
        ));
      }
      
      // Sort by last message time (newest first)
      conversations.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      
      state = state.copyWith(
        conversations: conversations,
        isLoading: false,
      );
    } catch (e) {
      Logger.error('Error loading conversations', e);
      state = state.copyWith(isLoading: false);
    }
  }

  void updateConversation(MessageModel message, String deviceName) {
    try {
      final otherDeviceId = message.isSent ? message.receiverId : message.senderId;
      
      // Try to get stored device name first, then use passed deviceName, then fallback to deviceId
      final storedName = DeviceStorage.getDeviceDisplayName(otherDeviceId);
      String finalDeviceName = storedName ?? (deviceName != otherDeviceId && deviceName.isNotEmpty ? deviceName : otherDeviceId);
      
      // If we got a proper name and it's not stored yet, store it
      if (deviceName != otherDeviceId && deviceName.isNotEmpty && deviceName != 'Unknown Device' && storedName == null) {
        DeviceStorage.setDeviceDisplayName(otherDeviceId, deviceName);
        finalDeviceName = deviceName;
      }
      
      // Add print for immediate visibility in logs
      print('🔵 updateConversation CALLED: senderId=${message.senderId}, receiverId=${message.receiverId}, otherDeviceId=$otherDeviceId');
      print('🔵 Message isSent=${message.isSent}, conversations count=${state.conversations.length}');
      print('🔵 Device name: stored=$storedName, passed=$deviceName, final=$finalDeviceName');
      
      Logger.info('=== updateConversation called ===');
      Logger.info('Message: isSent=${message.isSent}, senderId=${message.senderId}, receiverId=${message.receiverId}');
      Logger.info('otherDeviceId: $otherDeviceId, finalDeviceName: $finalDeviceName');
      Logger.info('Current conversations: ${state.conversations.length}');
      for (var conv in state.conversations) {
        print('  📋 Conversation: deviceId=${conv.deviceId}, lastMessage=${conv.lastMessage}');
        Logger.info('  - deviceId: ${conv.deviceId}, lastMessage: ${conv.lastMessage}');
      }
    
    // Try to find existing conversation by exact match first
    int existingIndex = state.conversations.indexWhere(
      (c) => c.deviceId == otherDeviceId,
    );
    
    print('🔍 Exact match check: existingIndex=$existingIndex, conversations count=${state.conversations.length}');
    Logger.info('Exact match found: ${existingIndex >= 0}');
    
    // CRITICAL: Even if we found an exact match, we need to check if there's a related conversation
    // with a different ID format (MAC vs UUID) that should be merged
    // This handles the case where Device 1 sends to MAC, Device 2 replies with UUID
    // Device 1 might have both conversations and we need to merge them
    String? conversationToMerge;
    int? conversationToMergeIndex;
    
    if (existingIndex >= 0) {
      // We found an exact match, but check if there's another conversation we should merge with
      // Only do this if the exact match is a MAC address and we're receiving/sending with a UUID (or vice versa)
      final currentConversation = state.conversations[existingIndex];
      final currentIsMAC = currentConversation.deviceId.contains(':');
      final newIsMAC = otherDeviceId.contains(':');
      
      // Only check for merging if ID formats differ (MAC vs UUID mismatch)
      // If formats match, no need to merge
      if (currentIsMAC != newIsMAC) {
        print('🔍 Found exact match at index $existingIndex (${currentConversation.deviceId}), but ID format differs. Checking for related conversations...');
        final allMessages = MessageStorage.getAllMessages();
        
        // Check if we have messages sent to/received from a different ID format
        // Scenario: We have conversation with MAC, but we're receiving from UUID (or vice versa)
        // We should check if there's another conversation that represents the same device
        for (int i = 0; i < state.conversations.length; i++) {
          final otherConv = state.conversations[i];
          if (otherConv.deviceId == otherDeviceId) continue; // Skip the exact match
          
          // Skip if the conversation IDs are the same format (both MAC or both UUID)
          // We only want to merge conversations with different ID formats
          final otherIsMAC = otherConv.deviceId.contains(':');
          if (currentIsMAC == otherIsMAC) {
            print('🔍 Skipping conversation $i (${otherConv.deviceId}): same ID format as current');
            continue; // Both are MAC or both are UUID, skip
          }
        
        // Check if we have bidirectional messages between current conversation and other conversation
        final sentToCurrent = allMessages.any((m) => m.isSent && m.receiverId == currentConversation.deviceId);
        final receivedFromOther = allMessages.any((m) => !m.isSent && m.senderId == otherConv.deviceId);
        final sentToOther = allMessages.any((m) => m.isSent && m.receiverId == otherConv.deviceId);
        final receivedFromCurrent = allMessages.any((m) => !m.isSent && m.senderId == currentConversation.deviceId);
        
        print('🔍 Checking conversation $i (${otherConv.deviceId}): sentToCurrent=$sentToCurrent, receivedFromOther=$receivedFromOther, sentToOther=$sentToOther, receivedFromCurrent=$receivedFromCurrent');
        
        // If we have messages in both directions, they're the same device
        // But only merge if we have clear bidirectional communication AND the new message fits the pattern
        final hasBidirectionalFlow = (sentToCurrent && receivedFromOther) || (sentToOther && receivedFromCurrent);
        
        if (hasBidirectionalFlow) {
          // Additional check: The new message should fit the bidirectional pattern
          // This prevents merging unrelated conversations
          final messageFitsPattern = (message.isSent && message.receiverId == otherDeviceId && sentToOther) ||
              (!message.isSent && message.senderId == otherDeviceId && receivedFromOther);
          
          if (messageFitsPattern) {
            print('🔗 Found related conversation at index $i: ${otherConv.deviceId} should be merged with ${currentConversation.deviceId}');
            conversationToMerge = otherConv.deviceId;
            conversationToMergeIndex = i;
            break;
          } else {
            print('🔍 Conversation $i has bidirectional flow but message doesn\'t fit pattern, skipping merge');
          }
        }
      }
      } else {
        print('🔍 Exact match found with same ID format, no merge needed');
      }
    }
    
    // If no exact match, try to find by checking if we have messages with this device
    // This handles cases where deviceId is UUID but message has MAC address or vice versa
    if (existingIndex < 0) {
      print('🔍 No exact match - entering matching logic for otherDeviceId=$otherDeviceId');
      // Get all messages to check for existing conversation with this device
      final allMessages = MessageStorage.getAllMessages();
      print('🔍 No exact match. Total messages: ${allMessages.length}, Conversations: ${state.conversations.length}');
      Logger.info('Total messages in storage: ${allMessages.length}');
      
      // CRITICAL FIX: Before complex matching, check ALL existing conversations for message-based matches
      // This handles multiple scenarios:
      // 1. Device A sent to Device B, now Device A receives from Device B
      // 2. Device B received from Device A (created conversation with UUID), now Device B receives with MAC
      // 3. Any bidirectional message flow between existing conversations and the new message
      if (existingIndex < 0) {
        print('🔍 Early matching check: Checking all conversations for message-based matches');
        
        // Check ALL conversations to see if we have message history with otherDeviceId
        for (int i = 0; i < state.conversations.length; i++) {
          final conv = state.conversations[i];
          
          // Check if we have ANY messages (sent or received) between conv.deviceId and otherDeviceId
          // This catches cases where:
          // - We received from conv.deviceId and are now receiving from otherDeviceId (same device, different IDs)
          // - We sent to conv.deviceId and are now receiving from otherDeviceId
          // - We received from conv.deviceId and are now sending to otherDeviceId
          
          final messagesWithConvDevice = allMessages.where((m) =>
            (m.isSent && m.receiverId == conv.deviceId) || 
            (!m.isSent && m.senderId == conv.deviceId)
          ).toList();
          
          final messagesWithOtherDevice = allMessages.where((m) =>
            (m.isSent && m.receiverId == otherDeviceId) || 
            (!m.isSent && m.senderId == otherDeviceId)
          ).toList();
          
          // Also include the current message if it matches
          final currentMessageMatches = (message.isSent && message.receiverId == otherDeviceId) ||
            (!message.isSent && message.senderId == otherDeviceId);
          if (currentMessageMatches && !messagesWithOtherDevice.any((m) => m.id == message.id)) {
            messagesWithOtherDevice.add(message);
          }
          
          // Check if we have bidirectional flow or if the new message connects them
          bool hasConnection = false;
          
          if (messagesWithConvDevice.isNotEmpty && messagesWithOtherDevice.isNotEmpty) {
            // We have messages with both IDs - check if they're related
            // Look for messages that link the two device IDs together
            // For example: message sent to conv.deviceId with senderId/receiverId that matches otherDeviceId
            
            // Check if we sent to conv.deviceId and received from otherDeviceId
            final sentToConv = messagesWithConvDevice.any((m) => m.isSent && m.receiverId == conv.deviceId);
            final receivedFromOther = messagesWithOtherDevice.any((m) => !m.isSent && m.senderId == otherDeviceId);
            
            // Check if we received from conv.deviceId and sent to otherDeviceId  
            final receivedFromConv = messagesWithConvDevice.any((m) => !m.isSent && m.senderId == conv.deviceId);
            final sentToOther = messagesWithOtherDevice.any((m) => m.isSent && m.receiverId == otherDeviceId);
            
            // If we have bidirectional flow or the new message creates a connection, they're the same device
            if ((sentToConv && receivedFromOther) || (receivedFromConv && sentToOther)) {
              hasConnection = true;
            }
            
            // Also check if the current message itself creates the connection
            if (!hasConnection) {
              if (message.isSent && message.receiverId == otherDeviceId && receivedFromConv) {
                hasConnection = true;
              } else if (!message.isSent && message.senderId == otherDeviceId && sentToConv) {
                hasConnection = true;
              }
            }
            } else if (messagesWithConvDevice.isNotEmpty) {
            // We have history with conv.deviceId but not with otherDeviceId yet
            // Check if the new message creates a connection
            // This is the KEY SCENARIO: Device B received from Device A (UUID), now receiving from Device A (MAC)
            
            final receivedFromConv = messagesWithConvDevice.any((m) => !m.isSent && m.senderId == conv.deviceId);
            final sentToConv = messagesWithConvDevice.any((m) => m.isSent && m.receiverId == conv.deviceId);
            
            if (!message.isSent && message.senderId == otherDeviceId) {
              // We're receiving from otherDeviceId - check if we previously received from conv.deviceId
              // and they might be the same device (different ID formats: UUID vs MAC)
              
              if (receivedFromConv) {
                // We've received from conv.deviceId before
                // Check if we've sent messages to either - if we've sent to conv.deviceId but not otherDeviceId,
                // or vice versa, they're likely the same device
                final sentToOther = allMessages.any((m) => m.isSent && m.receiverId == otherDeviceId);
                
                // If we received from conv.deviceId and are now receiving from otherDeviceId,
                // and we haven't sent to both separately (which would indicate they're different devices),
                // they're likely the same device with different ID formats
                if (!sentToConv || !sentToOther || (sentToConv && sentToOther)) {
                  // Either we haven't sent to either, or we've sent to both - they're likely the same device
                  hasConnection = true;
                  print('🔍 Linking: received from ${conv.deviceId}, now receiving from $otherDeviceId (same device, different IDs - UUID vs MAC)');
                }
              }
            } else if (message.isSent && message.receiverId == otherDeviceId) {
              // We're sending to otherDeviceId - check if we have history with conv.deviceId
              // If we received from conv.deviceId and are now sending to otherDeviceId,
              // they might be the same device (we're replying to the conversation)
              if (receivedFromConv || sentToConv) {
                // We have history with conv.deviceId - if we're now sending to otherDeviceId,
                // they're likely the same device (different ID formats)
                hasConnection = true;
                print('🔍 Linking: history with ${conv.deviceId}, now sending to $otherDeviceId (replying to conversation)');
              }
            }
          }
          
          if (hasConnection) {
            existingIndex = i;
            print('✅ MATCHED (Early): Found conversation at index $i by message history');
            print('✅ conv.deviceId=${conv.deviceId} <-> otherDeviceId=$otherDeviceId (bidirectional flow detected)');
            Logger.info('✓ MATCHED (Early): Conversation index $i - deviceId=${conv.deviceId} matches otherDeviceId=$otherDeviceId');
            break;
          }
        }
      }
      
      // Find if we have any messages with this device (by checking senderId/receiverId)
      // Only do this if we haven't found a match yet
      String? existingConversationId;
      
      // Only run complex matching if we haven't found a match in the early check
      if (existingIndex < 0) {
      for (final existingConv in state.conversations) {
        print('🔍 Checking conversation: deviceId=${existingConv.deviceId}');
        Logger.info('Checking conversation with deviceId: ${existingConv.deviceId}');
        
        // CRITICAL MATCHING LOGIC:
        // We need to match conversations even when deviceId formats differ (UUID vs MAC)
        // Strategy: Check if we have bidirectional messages between existingConv.deviceId and otherDeviceId
        
        bool foundMatch = false;
        
        // Check 1: Most direct case - we sent TO existingConv.deviceId and we're receiving FROM otherDeviceId
        // This is the key scenario: Device 1 sends to Device 2's MAC, Device 2 replies with Device 2's UUID
        final messagesSentToExisting = allMessages.where((m) => m.isSent && m.receiverId == existingConv.deviceId).toList();
        final weSentToExisting = messagesSentToExisting.isNotEmpty;
        
        print('🔍 Check 1: weSentToExisting=$weSentToExisting, message.isSent=${message.isSent}, existingConv.deviceId=${existingConv.deviceId}, otherDeviceId=$otherDeviceId');
        Logger.info('Check 1: weSentToExisting=$weSentToExisting (found ${messagesSentToExisting.length} messages sent to ${existingConv.deviceId})');
        if (messagesSentToExisting.isNotEmpty) {
          Logger.info('  Sample sent message: receiverId=${messagesSentToExisting.first.receiverId}');
        }
        Logger.info('  Current message: isSent=${message.isSent}, senderId=${message.senderId}, otherDeviceId=$otherDeviceId');
        
        // When receiving (!message.isSent), otherDeviceId == message.senderId
        // Key scenario: Device 1 sends to Device 2's MAC, Device 2 replies with Device 2's UUID
        // We need to match: we sent to existingConv.deviceId (MAC) AND we're receiving from otherDeviceId (UUID)
        if (weSentToExisting && !message.isSent) {
          // Find the most recent message we sent to this conversation's deviceId
          final mostRecentSent = messagesSentToExisting.isNotEmpty
              ? messagesSentToExisting.reduce((a, b) => 
                  a.timestamp.isAfter(b.timestamp) ? a : b
                )
              : null;
          
          if (mostRecentSent != null) {
            // Check if the received message is recent (within 30 minutes of our sent message)
            // This helps ensure we're matching the right conversation
            final timeDiff = message.timestamp.difference(mostRecentSent.timestamp).abs();
            final isRecentReply = timeDiff.inMinutes < 30;
            
            print('🔍 Check 1 time check: timeDiff=${timeDiff.inSeconds}s, isRecentReply=$isRecentReply');
            
            if (isRecentReply) {
              // We previously sent to existingConv.deviceId, and we're now receiving from otherDeviceId
              // The timing suggests this is a reply, so they're the same device
              // (existingConv.deviceId might be MAC, otherDeviceId might be UUID, or vice versa)
              foundMatch = true;
              print('✅ MATCHED (Check 1): Sent to ${existingConv.deviceId}, receiving from $otherDeviceId (${timeDiff.inSeconds}s ago)');
              Logger.info('✓ MATCHED (Check 1): Sent to ${existingConv.deviceId}, receiving from $otherDeviceId (recent reply, ${timeDiff.inSeconds}s ago)');
            } else {
              print('❌ Check 1: Message too old (${timeDiff.inMinutes}m ago)');
              Logger.info('✗ Check 1: Received message too old (${timeDiff.inMinutes}m ago)');
            }
          } else {
            print('❌ Check 1: mostRecentSent is null');
          }
        } else {
          print('❌ Check 1: Condition not met (weSentToExisting=$weSentToExisting, message.isSent=${message.isSent})');
        }
        
        // Check 2: Reverse case - we received FROM existingConv.deviceId and we're sending TO otherDeviceId
        if (!foundMatch) {
          final messagesReceivedFromExisting = allMessages.where((m) => !m.isSent && m.senderId == existingConv.deviceId).toList();
          final weReceivedFromExisting = messagesReceivedFromExisting.isNotEmpty;
          Logger.info('Check 2: weReceivedFromExisting=$weReceivedFromExisting (found ${messagesReceivedFromExisting.length} messages)');
          
          if (weReceivedFromExisting && message.isSent && message.receiverId == otherDeviceId) {
            foundMatch = true;
            Logger.info('✓ MATCHED (Check 2): Received from ${existingConv.deviceId}, sending to $otherDeviceId');
          }
        }
        
        // Check 3: Bidirectional flow - if we have messages in both directions, they're the same device
        if (!foundMatch) {
          final sentToExisting = allMessages.any((m) => m.isSent && m.receiverId == existingConv.deviceId);
          final receivedFromOther = allMessages.any((m) => !m.isSent && m.senderId == otherDeviceId);
          final receivedFromExisting = allMessages.any((m) => !m.isSent && m.senderId == existingConv.deviceId);
          final sentToOther = allMessages.any((m) => m.isSent && m.receiverId == otherDeviceId);
          
          print('🔍 Check 3: sentToExisting=$sentToExisting, receivedFromOther=$receivedFromOther, receivedFromExisting=$receivedFromExisting, sentToOther=$sentToOther');
          Logger.info('Check 3: sentToExisting=$sentToExisting, receivedFromOther=$receivedFromOther, receivedFromExisting=$receivedFromExisting, sentToOther=$sentToOther');
          
          // If we have messages in both directions (sent to one, received from the other), they're the same device
          // Improved logic: Check if we sent to existing and are receiving from other (or vice versa)
          // OR if we sent to other and received from existing
          if ((sentToExisting && receivedFromOther) || (receivedFromExisting && sentToOther)) {
            // Also verify the new message fits this pattern
            // For receiving: if we sent to existing and are receiving from other, match!
            // For sending: if we received from existing and are sending to other, match!
            final messageFitsPattern = 
                (!message.isSent && message.senderId == otherDeviceId && sentToExisting) ||
                (message.isSent && message.receiverId == otherDeviceId && receivedFromExisting);
            
            if (messageFitsPattern) {
              foundMatch = true;
              print('✅ MATCHED (Check 3): Bidirectional flow between ${existingConv.deviceId} and $otherDeviceId');
              Logger.info('✓ MATCHED (Check 3): Bidirectional flow between ${existingConv.deviceId} and $otherDeviceId');
            }
          }
          
          // Additional check: If we sent messages TO otherDeviceId and this conversation has those messages
          // This catches the case where conversation.deviceId == otherDeviceId but exact match failed due to format
          if (!foundMatch && sentToOther && existingConv.deviceId == otherDeviceId) {
            foundMatch = true;
            existingIndex = state.conversations.indexOf(existingConv);
            print('✅ MATCHED (Check 3b): Direct match - sent to otherDeviceId matches conversation deviceId');
            Logger.info('✓ MATCHED (Check 3b): Direct match found');
          }
        }
        
        // Check 4: Fallback - if we recently sent to existingConv.deviceId and we're receiving from otherDeviceId,
        // and there are no other conversations, assume they're the same (most recent conversation)
        if (!foundMatch && !message.isSent && weSentToExisting) {
          // If this is the most recent conversation (by lastMessageTime), it's likely the same device
          final isMostRecent = state.conversations.isEmpty || 
              existingConv.lastMessageTime == state.conversations
                  .map((c) => c.lastMessageTime)
                  .reduce((a, b) => a.isAfter(b) ? a : b);
          
          if (isMostRecent) {
            // Check if the time between our last sent message and this received message is reasonable
            if (messagesSentToExisting.isNotEmpty) {
              final mostRecentSent = messagesSentToExisting.reduce((a, b) => 
                  a.timestamp.isAfter(b.timestamp) ? a : b
                );
              final timeDiff = message.timestamp.difference(mostRecentSent.timestamp).abs();
              
              // If within 1 hour, consider it a match (more lenient than Check 1)
              if (timeDiff.inHours < 1) {
                foundMatch = true;
                print('✅ MATCHED (Check 4 - Fallback): Most recent conversation, timeDiff=${timeDiff.inSeconds}s');
                Logger.info('✓ MATCHED (Check 4 - Fallback): Most recent conversation, timeDiff=${timeDiff.inSeconds}s');
              }
            }
          }
        }
        
        if (foundMatch) {
          existingConversationId = existingConv.deviceId;
          print('✅✅✅ FOUND MATCH: existing deviceId=${existingConv.deviceId}, new deviceId=$otherDeviceId');
          Logger.info('✓✓✓ Found existing conversation by message matching: existing deviceId=${existingConv.deviceId}, new deviceId=$otherDeviceId');
          break;
        } else {
          print('❌ No match for conversation: ${existingConv.deviceId}');
          Logger.info('✗ No match found for conversation with deviceId: ${existingConv.deviceId}');
        }
      }
      } // End of if (existingIndex < 0) for complex matching
      
      // If we found an existing conversation, use it
      if (existingConversationId != null && existingIndex < 0) {
        existingIndex = state.conversations.indexWhere(
          (c) => c.deviceId == existingConversationId,
        );
        print('✅ Using existing conversation at index: $existingIndex');
        Logger.info('Found existing conversation at index: $existingIndex');
      } else if (existingIndex < 0) {
        // Only show warning if we haven't found a match in early check
        print('⚠️ No existing conversation found - will create new one for: $otherDeviceId');
        Logger.warning('No existing conversation found for otherDeviceId: $otherDeviceId');
        Logger.warning('This will create a new conversation');
      }
    }
    
    // If we found a related conversation to merge, handle it
    if (conversationToMerge != null && conversationToMergeIndex != null && existingIndex >= 0) {
      final mergeIndex = conversationToMergeIndex;
      
      // Double-check that the conversations still exist and haven't been merged already
      if (mergeIndex >= state.conversations.length || 
          state.conversations[mergeIndex].deviceId != conversationToMerge) {
        print('⚠️ Conversation to merge no longer exists or already merged, skipping');
      } else {
        print('🔗 Merging conversations: index $existingIndex (${state.conversations[existingIndex].deviceId}) with index $mergeIndex ($conversationToMerge)');
        
        final conv1 = state.conversations[existingIndex];
        final conv2 = state.conversations[mergeIndex];
        
        // Prefer UUID over MAC address (UUIDs don't contain colons)
        // Always use UUID if available, otherwise use the more recent one
        final isConv1UUID = !conv1.deviceId.contains(':');
        final isConv2UUID = !conv2.deviceId.contains(':');
        final preferredId = isConv1UUID ? conv1.deviceId : (isConv2UUID ? conv2.deviceId : conv1.deviceId);
        
        print('🔗 Merge: conv1.deviceId=${conv1.deviceId} (UUID=$isConv1UUID), conv2.deviceId=${conv2.deviceId} (UUID=$isConv2UUID), preferredId=$preferredId');
        
        // Merge messages and update
        final mergedUnreadCount = conv1.unreadCount + conv2.unreadCount;
        final mergedLastMessage = conv1.lastMessageTime.isAfter(conv2.lastMessageTime) ? conv1.lastMessage : conv2.lastMessage;
        final mergedLastMessageTime = conv1.lastMessageTime.isAfter(conv2.lastMessageTime) ? conv1.lastMessageTime : conv2.lastMessageTime;
        
        final updatedList = List<ConversationModel>.from(state.conversations);
        updatedList[existingIndex] = conv1.copyWith(
          deviceId: preferredId,
          unreadCount: mergedUnreadCount,
          lastMessage: mergedLastMessage,
          lastMessageTime: mergedLastMessageTime,
        );
        updatedList.removeAt(mergeIndex);
        updatedList.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
        
        // Find the new index after removal
        existingIndex = updatedList.indexWhere((c) => c.deviceId == preferredId);
        
        state = state.copyWith(conversations: updatedList);
        print('✅ Conversations merged successfully, new index: $existingIndex');
      }
    }
    
    if (existingIndex >= 0) {
      // Update existing conversation
      print('✅ Updating existing conversation at index $existingIndex for device: $otherDeviceId');
      final existing = state.conversations[existingIndex];
      final unreadCount = message.isSent 
          ? existing.unreadCount 
          : existing.unreadCount + 1;
      
      // CRITICAL FIX: ALWAYS prefer UUID over MAC address for consistency
      // If we found a match and the conversation has a UUID but the new message has a MAC,
      // keep the UUID. This ensures all messages use the same conversation.
      final currentIsMAC = existing.deviceId.contains(':');
      final newIsMAC = otherDeviceId.contains(':');
      String preferredDeviceId;
      
      if (!currentIsMAC && !newIsMAC) {
        // Both are UUIDs - keep the existing one (they should match anyway)
        preferredDeviceId = existing.deviceId;
      } else if (!currentIsMAC && newIsMAC) {
        // Current is UUID, new is MAC - keep UUID (prefer existing conversation's ID)
        preferredDeviceId = existing.deviceId;
        print('🔧 Keeping UUID from existing conversation: ${existing.deviceId} (ignoring MAC: $otherDeviceId)');
      } else if (currentIsMAC && !newIsMAC) {
        // Current is MAC, new is UUID - use UUID (upgrade to UUID)
        preferredDeviceId = otherDeviceId;
        print('🔧 Upgrading from MAC to UUID: ${existing.deviceId} -> $otherDeviceId');
      } else {
        // Both are MACs - use the existing one to maintain consistency
        preferredDeviceId = existing.deviceId;
      }
      
      print('🔧 Updating deviceId: current=${existing.deviceId} (MAC=$currentIsMAC), new=$otherDeviceId (MAC=$newIsMAC), preferred=$preferredDeviceId');
      
      final updated = existing.copyWith(
        deviceId: preferredDeviceId,
        lastMessage: message.content,
        lastMessageTime: message.timestamp,
        unreadCount: unreadCount,
        deviceName: finalDeviceName,
      );
      
      final updatedList = List<ConversationModel>.from(state.conversations);
      updatedList[existingIndex] = updated;
      updatedList.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      
      state = state.copyWith(conversations: updatedList);
      print('✅ Conversation updated successfully with deviceId: $preferredDeviceId');
      Logger.info('Updated existing conversation: deviceId changed from ${existing.deviceId} to $preferredDeviceId');
    } else {
      // Create new conversation - but first check if we should merge with an existing one
      // that has a different ID format (MAC vs UUID)
      print('⚠️ Creating NEW conversation for device: $otherDeviceId (no match found)');
      
      // Last check: If otherDeviceId is a MAC address, check if we have a UUID conversation
      // with bidirectional messages (or vice versa)
      final otherIsMAC = otherDeviceId.contains(':');
      String? conversationToMergeId;
      
      if (otherIsMAC) {
        // We're creating a MAC conversation - check if we have a UUID conversation with the same device
        final allMessages = MessageStorage.getAllMessages();
        
        for (final existingConv in state.conversations) {
          final existingIsMAC = existingConv.deviceId.contains(':');
          
          // Only check UUID conversations
          if (!existingIsMAC) {
            // Check if we have bidirectional messages between the UUID and this MAC
            final messagesWithUUID = allMessages.where((m) =>
              (m.isSent && m.receiverId == existingConv.deviceId) ||
              (!m.isSent && m.senderId == existingConv.deviceId)
            ).toList();
            
            // Check if we have messages with the MAC (from the current message)
            final messagesWithMAC = allMessages.where((m) =>
              (m.isSent && m.receiverId == otherDeviceId) ||
              (!m.isSent && m.senderId == otherDeviceId)
            ).toList();
            
            // If we have messages with both, they're likely the same device
            if (messagesWithUUID.isNotEmpty && messagesWithMAC.isNotEmpty) {
              // Check for bidirectional flow
              final sentToUUID = messagesWithUUID.any((m) => m.isSent && m.receiverId == existingConv.deviceId);
              final receivedFromMAC = messagesWithMAC.any((m) => !m.isSent && m.senderId == otherDeviceId);
              final receivedFromUUID = messagesWithUUID.any((m) => !m.isSent && m.senderId == existingConv.deviceId);
              final sentToMAC = messagesWithMAC.any((m) => m.isSent && m.receiverId == otherDeviceId);
              
              if ((sentToUUID && receivedFromMAC) || (receivedFromUUID && sentToMAC)) {
                conversationToMergeId = existingConv.deviceId;
                print('🔗 Found related UUID conversation: ${existingConv.deviceId} - will merge instead of creating new MAC conversation');
                break;
              }
            }
          }
        }
      }
      
      if (conversationToMergeId != null) {
        // Merge with existing conversation instead of creating new one
        existingIndex = state.conversations.indexWhere((c) => c.deviceId == conversationToMergeId);
        if (existingIndex >= 0) {
          final existing = state.conversations[existingIndex];
          final unreadCount = message.isSent 
              ? existing.unreadCount 
              : existing.unreadCount + 1;
          
          final updated = existing.copyWith(
            deviceId: conversationToMergeId, // Keep UUID
            lastMessage: message.content,
            lastMessageTime: message.timestamp,
            unreadCount: unreadCount,
            deviceName: finalDeviceName,
          );
          
          final updatedList = List<ConversationModel>.from(state.conversations);
          updatedList[existingIndex] = updated;
          updatedList.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
          
          state = state.copyWith(conversations: updatedList);
          print('✅ Merged into existing UUID conversation at index $existingIndex');
          Logger.info('Merged MAC conversation ($otherDeviceId) into UUID conversation ($conversationToMergeId)');
        }
      } else {
        // No merge found - create new conversation
        final newConversation = ConversationModel(
          deviceId: otherDeviceId,
          deviceName: finalDeviceName,
          lastMessage: message.content,
          lastMessageTime: message.timestamp,
          unreadCount: message.isSent ? 0 : 1,
        );
        
        final updatedList = [newConversation, ...state.conversations];
        updatedList.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
        
        state = state.copyWith(conversations: updatedList);
        print('⚠️ New conversation created');
        Logger.info('Created new conversation for device: $otherDeviceId');
      }
    }
    } catch (e, stackTrace) {
      print('❌ ERROR in updateConversation: $e');
      print('❌ Stack trace: $stackTrace');
      Logger.error('Error in updateConversation', e, stackTrace);
      rethrow;
    }
  }

  void markAsRead(String deviceId) {
    final index = state.conversations.indexWhere((c) => c.deviceId == deviceId);
    if (index >= 0) {
      final updated = state.conversations[index].copyWith(unreadCount: 0);
      final updatedList = List<ConversationModel>.from(state.conversations);
      updatedList[index] = updated;
      state = state.copyWith(conversations: updatedList);
    }
  }

  void refresh() {
    _loadConversations();
  }
}

final conversationsProvider = StateNotifierProvider<ConversationsNotifier, ConversationsState>((ref) {
  return ConversationsNotifier();
});
