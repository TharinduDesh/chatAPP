// lib/services/socket_service.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/api_constants.dart';
import 'auth_service.dart';
import 'dart:async';
import '../models/message_model.dart';
import '../models/conversation_model.dart';

class SocketService {
  IO.Socket? _socket;
  final AuthService _authService;

  final StreamController<Message> _messageStreamController =
      StreamController<Message>.broadcast();
  Stream<Message> get messageStream => _messageStreamController.stream;

  final StreamController<List<String>> _activeUsersStreamController =
      StreamController<List<String>>.broadcast();
  Stream<List<String>> get activeUsersStream =>
      _activeUsersStreamController.stream;

  final StreamController<Map<String, dynamic>> _typingStatusStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get typingStatusStream =>
      _typingStatusStreamController.stream;

  final StreamController<Conversation> _conversationUpdateStreamController =
      StreamController<Conversation>.broadcast();
  Stream<Conversation> get conversationUpdateStream =>
      _conversationUpdateStreamController.stream;

  // <<< NEW: Stream for message status updates (delivered/read) >>>
  final StreamController<Map<String, dynamic>>
  _messageStatusUpdateStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStatusUpdateStream =>
      _messageStatusUpdateStreamController.stream;

  SocketService(this._authService);

  IO.Socket? get socket => _socket;

  void connect() {
    final String? currentUserId = _authService.currentUser?.id;
    if (currentUserId == null) return;
    if (_socket != null && _socket!.connected) return; // Already connected

    print('SocketService: Attempting to connect with user ID: $currentUserId');
    _socket = IO.io(SERVER_ROOT_URL, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'forceNew': true,
      'query': {'userId': currentUserId},
    });

    // --- All Listeners ---
    _socket!.onConnect(
      (_) => print('SocketService: Connected! ID: ${_socket?.id}'),
    );
    _socket!.onDisconnect(
      (reason) => print('SocketService: Disconnected. Reason: $reason'),
    );
    _socket!.onConnectError(
      (data) => print('SocketService: Connection Error: $data'),
    );
    _socket!.onError((data) => print('SocketService: Error: $data'));

    _socket!.on('receiveMessage', (data) {
      try {
        if (data is Map<String, dynamic>) {
          _messageStreamController.add(Message.fromJson(data));
        }
      } catch (e) {
        print('SocketService: Error parsing receiveMessage: $e');
      }
    });

    _socket!.on('activeUsers', (data) {
      if (data is List)
        _activeUsersStreamController.add(
          List<String>.from(data.map((item) => item.toString())),
        );
    });

    _socket!.on('userTyping', (data) {
      if (data is Map<String, dynamic>) _typingStatusStreamController.add(data);
    });

    _socket!.on('conversationUpdated', (data) {
      try {
        if (data is Map<String, dynamic>)
          _conversationUpdateStreamController.add(Conversation.fromJson(data));
      } catch (e) {
        print('SocketService: Error parsing conversationUpdated: $e');
      }
    });

    // <<< NEW: Listeners for read receipt events >>>
    _socket!.on('messageDelivered', (data) {
      print("SocketService: Received messageDelivered: $data");
      if (data is Map<String, dynamic>) {
        _messageStatusUpdateStreamController.add({
          'conversationId': data['conversationId'],
          'messageId': data['messageId'],
          'status': 'delivered',
        });
      }
    });

    _socket!.on('messagesRead', (data) {
      print("SocketService: Received messagesRead: $data");
      if (data is Map<String, dynamic>) {
        _messageStatusUpdateStreamController.add({
          'conversationId': data['conversationId'],
          'status': 'read', // This event indicates ALL messages are read
        });
      }
    });
  }

  void sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
  }) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('sendMessage', {
        'conversationId': conversationId,
        'senderId': senderId,
        'content': content,
      });
    }
  }

  // <<< NEW: Method to emit mark as read event >>>
  void markMessagesAsRead(String conversationId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('markMessagesAsRead', {'conversationId': conversationId});
      print(
        "SocketService: Emitted markMessagesAsRead for convo: $conversationId",
      );
    }
  }

  // ... (all other existing methods like joinConversation, leave, disconnect, etc.) ...
  void joinConversation(String conversationId) {
    if (_socket != null && _socket!.connected)
      _socket!.emit('joinConversation', conversationId);
  }

  void leaveConversation(String conversationId) {
    if (_socket != null && _socket!.connected)
      _socket!.emit('leaveConversation', conversationId);
  }

  void emitTyping(String conversationId, String userId, String userName) {
    if (_socket != null && _socket!.connected)
      _socket!.emit('typing', {
        'conversationId': conversationId,
        'userId': userId,
        'userName': userName,
      });
  }

  void emitStopTyping(String conversationId, String userId, String userName) {
    if (_socket != null && _socket!.connected)
      _socket!.emit('stopTyping', {
        'conversationId': conversationId,
        'userId': userId,
        'userName': userName,
      });
  }

  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }
  }

  void disposeStreams() {
    _messageStreamController.close();
    _activeUsersStreamController.close();
    _typingStatusStreamController.close();
    _conversationUpdateStreamController.close();
    _messageStatusUpdateStreamController.close(); // <<< NEW: Dispose stream
  }
}
