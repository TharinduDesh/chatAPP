// lib/services/socket_service.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/api_constants.dart';
import 'auth_service.dart';
import 'dart:async';
import '../models/message_model.dart';
import '../models/conversation_model.dart';
import 'package:cryptography/cryptography.dart';

import 'crypto_service.dart';

enum SocketStatus { connecting, online, offline }

class SocketService {
  IO.Socket? _socket;
  final AuthService _authService;
  final CryptoService _cryptoService = CryptoService();

  // Controllers are now late, as they will be initialized on demand
  late StreamController<SocketStatus> _connectionStatusController;
  late StreamController<Message> _messageStreamController;
  late StreamController<Message> _messageUpdateStreamController;
  late StreamController<List<String>> _activeUsersStreamController;
  late StreamController<Map<String, dynamic>> _typingStatusStreamController;
  late StreamController<Conversation> _conversationUpdateStreamController;
  late StreamController<Map<String, dynamic>>
  _messageStatusUpdateStreamController;
  late StreamController<Map<String, dynamic>> _groupKeyStreamController;

  Stream<SocketStatus> get connectionStatusStream =>
      _connectionStatusController.stream;
  Stream<Message> get messageStream => _messageStreamController.stream;
  Stream<Message> get messageUpdateStream =>
      _messageUpdateStreamController.stream;
  Stream<List<String>> get activeUsersStream =>
      _activeUsersStreamController.stream;
  Stream<Map<String, dynamic>> get typingStatusStream =>
      _typingStatusStreamController.stream;
  Stream<Conversation> get conversationUpdateStream =>
      _conversationUpdateStreamController.stream;
  Stream<Map<String, dynamic>> get messageStatusUpdateStream =>
      _messageStatusUpdateStreamController.stream;
  Stream<Map<String, dynamic>> get groupKeyStream =>
      _groupKeyStreamController.stream;

  SocketStatus _lastStatus = SocketStatus.offline;
  SocketStatus get lastStatus => _lastStatus;

  List<String> _lastActiveUsers = [];
  List<String> get lastActiveUsers => _lastActiveUsers;

  IO.Socket? get socket => _socket;

  // Constructor now calls init()
  SocketService(this._authService) {
    init();
  }

  /// Initializes fresh StreamControllers for a new session.
  void init() {
    // If controllers already exist and are open, close them before creating new ones.
    if (this.isInitialized && !_connectionStatusController.isClosed) {
      _closeStreams();
    }

    _connectionStatusController = StreamController<SocketStatus>.broadcast();
    _messageStreamController = StreamController<Message>.broadcast();
    _messageUpdateStreamController = StreamController<Message>.broadcast();
    _activeUsersStreamController = StreamController<List<String>>.broadcast();
    _typingStatusStreamController =
        StreamController<Map<String, dynamic>>.broadcast();
    _conversationUpdateStreamController =
        StreamController<Conversation>.broadcast();
    _messageStatusUpdateStreamController =
        StreamController<Map<String, dynamic>>.broadcast();
    _groupKeyStreamController =
        StreamController<Map<String, dynamic>>.broadcast();

    _lastStatus = SocketStatus.offline;
    _connectionStatusController.add(_lastStatus);
  }

  // Helper to check if controllers have been initialized.
  bool get isInitialized => 'this'.allMatches(this.toString()).isNotEmpty;

  /// Closes all streams.
  void _closeStreams() {
    _connectionStatusController.close();
    _messageStreamController.close();
    _messageUpdateStreamController.close();
    _activeUsersStreamController.close();
    _typingStatusStreamController.close();
    _conversationUpdateStreamController.close();
    _messageStatusUpdateStreamController.close();
    _groupKeyStreamController.close();
  }

  /// The main public method to completely shut down the service.
  void dispose() {
    disconnect();
    _closeStreams();
  }

  void connect() {
    final String? currentUserId = _authService.currentUser?.id;
    if (currentUserId == null) {
      print('SocketService: Connect failed, user is null.');
      return;
    }
    if (_socket != null && _socket!.connected) return;

    print('SocketService: Attempting to connect with user ID: $currentUserId');
    _updateStatus(SocketStatus.connecting);

    // Ensure we have a clean slate before creating a new socket
    if (_socket != null) {
      _socket!.dispose();
    }

    _socket = IO.io(SERVER_ROOT_URL, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'forceNew': true,
      'query': {'userId': currentUserId},
      // Adding reconnection settings for more robustness
      'reconnection': true,
      'reconnectionAttempts': 5,
      'reconnectionDelay': 2000,
    });

    _socket!.onConnect((_) {
      print('SocketService: Connected! ID: ${_socket?.id}');
      _updateStatus(SocketStatus.online);
    });
    _socket!.onDisconnect((reason) {
      print('SocketService: Disconnected. Reason: $reason');
      _updateStatus(SocketStatus.offline);
    });
    _socket!.onConnectError((data) {
      print('SocketService: Connection Error: $data');
      _updateStatus(SocketStatus.offline);
    });
    _socket!.onError((data) {
      print('SocketService: Error: $data');
      _updateStatus(SocketStatus.offline);
    });

    // --- All other event listeners remain the same ---
    _socket!.on('receiveMessage', (data) {
      try {
        if (data is Map<String, dynamic>) {
          final message = Message.fromJson(data);
          _messageStreamController.add(message);
        }
      } catch (e) {
        print('❌ SocketService: Error parsing receiveMessage: $e');
      }
    });

    _socket!.on('receiveGroupKey', (data) {
      print("SOCKET_INFO: Received group key data: $data");
      if (data is Map<String, dynamic>) {
        final conversationId = data['conversationId'];
        final encryptedKey = data['encryptedKey'];
        final senderId = data['senderId'];

        if (conversationId != null &&
            encryptedKey != null &&
            senderId != null) {
          _cryptoService.decryptAndStoreGroupKey(
            conversationId,
            encryptedKey,
            senderId,
          );
        }
      }
    });

    _socket!.on('activeUsers', (data) {
      if (data is List) {
        _lastActiveUsers = List<String>.from(
          data.map((item) => item.toString()),
        );
        _activeUsersStreamController.add(_lastActiveUsers);
      }
    });

    _socket!.on('userTyping', (data) {
      if (data is Map<String, dynamic>) _typingStatusStreamController.add(data);
    });

    _socket!.on('conversationUpdated', (data) {
      try {
        if (data is Map<String, dynamic>) {
          _conversationUpdateStreamController.add(Conversation.fromJson(data));
        }
      } catch (e) {
        print('SocketService: Error parsing conversationUpdated: $e');
      }
    });

    _socket!.on('messageUpdated', (data) {
      try {
        if (data is Map<String, dynamic>) {
          _messageUpdateStreamController.add(Message.fromJson(data));
        }
      } catch (e) {
        print('SocketService: Error parsing messageUpdated: $e');
      }
    });

    _socket!.on('messageDelivered', (data) {
      if (data is Map<String, dynamic>) {
        _messageStatusUpdateStreamController.add({
          'conversationId': data['conversationId'],
          'messageId': data['messageId'],
          'status': 'delivered',
        });
      }
    });

    _socket!.on('messagesRead', (data) {
      if (data is Map<String, dynamic>) {
        _messageStatusUpdateStreamController.add({
          'conversationId': data['conversationId'],
          'status': 'read',
        });
      }
    });
  }

  void _updateStatus(SocketStatus status) {
    _lastStatus = status;
    if (!_connectionStatusController.isClosed) {
      _connectionStatusController.add(status);
    }
  }

  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _updateStatus(SocketStatus.offline);
    }
  }

  // All other methods (sendMessage, shareGroupKey, etc.) remain unchanged.
  void sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
    String? recipientId,
    bool isEncrypted = false,
    String? fileUrl,
    String? fileType,
    String? fileName,
    String? replyTo,
    String? replySnippet,
    String? replySenderName,
  }) async {
    await _cryptoService.ready;
    if (_socket == null || !_socket!.connected) return;

    String contentToSend = content;
    bool isEncryptedForEmit = isEncrypted;

    if (isEncryptedForEmit && fileUrl == null) {
      String? encryptedContent;
      if (recipientId != null) {
        encryptedContent = await _cryptoService.encryptMessage(
          recipientId,
          content,
        );
      } else {
        encryptedContent = await _cryptoService.encryptGroupMessage(
          conversationId,
          content,
        );
      }

      if (encryptedContent != null) {
        contentToSend = encryptedContent;
        print("✅ Message encrypted successfully.");
      } else {
        print("❌ Encryption failed. Sending message as plaintext.");
        isEncryptedForEmit = false;
      }
    }

    _socket!.emit('sendMessage', {
      'conversationId': conversationId,
      'senderId': senderId,
      'content': contentToSend,
      'isEncrypted': isEncryptedForEmit,
      'fileUrl': fileUrl,
      'fileType': fileType,
      'fileName': fileName,
      'replyTo': replyTo,
      'replySnippet': replySnippet,
      'replySenderName': replySenderName,
    });
  }

  void shareGroupKey(String conversationId, String recipientId) async {
    final senderId = _authService.currentUser?.id;
    if (senderId == null) return;

    await _cryptoService.ready;

    final SecretKey groupKey = await _cryptoService.getOrGenerateGroupKey(
      conversationId,
    );
    final String? encryptedKey = await _cryptoService.encryptGroupKeyForUser(
      groupKey,
      recipientId,
    );

    if (encryptedKey != null) {
      _socket!.emit('shareGroupKey', {
        'conversationId': conversationId,
        'senderId': senderId,
        'recipientId': recipientId,
        'encryptedKey': encryptedKey,
      });
      print("🔑 Emitted shareGroupKey event to server for user $recipientId.");
    } else {
      print("❌ Failed to encrypt group key for sharing.");
    }
  }

  void markMessagesAsRead(String conversationId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('markMessagesAsRead', {'conversationId': conversationId});
    }
  }

  void reactToMessage(String conversationId, String messageId, String emoji) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('reactToMessage', {
        'conversationId': conversationId,
        'messageId': messageId,
        'emoji': emoji,
      });
    }
  }

  void joinConversation(String conversationId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('joinConversation', conversationId);
    }
  }

  void leaveConversation(String conversationId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('leaveConversation', conversationId);
    }
  }

  void emitTyping(String conversationId, String userId, String userName) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('typing', {
        'conversationId': conversationId,
        'userId': userId,
        'userName': userName,
      });
    }
  }

  void emitStopTyping(String conversationId, String userId, String userName) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('stopTyping', {
        'conversationId': conversationId,
        'userId': userId,
        'userName': userName,
      });
    }
  }
}
