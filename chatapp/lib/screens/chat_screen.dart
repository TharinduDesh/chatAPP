// lib/screens/chat_screen.dart
import 'dart:async';
import 'dart:io'; // For File
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // For ImagePicker
import 'package:file_picker/file_picker.dart';
import '../services/services_locator.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../widgets/user_avatar.dart';
import '../config/api_constants.dart';
import 'package:intl/intl.dart';
import 'home_screen.dart';
import 'add_members_to_group_screen.dart';
import 'file_preview_screen.dart';
import 'photo_viewer_screen.dart';
import 'syncfusion_pdf_viewer_screen.dart';
import 'package:record/record.dart';
import '../widgets/voice_message_bubble.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/reaction_model.dart';

// --- ADDED: Import for CryptoService ---
import '../services/crypto_service.dart';
import '../services/cache_service.dart';
import '../services/socket_service.dart';

import '../config/api_constants.dart';
import 'profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;
  final User otherUser;

  const ChatScreen({
    super.key,
    required this.conversation,
    required this.otherUser,
  });

  static const String routeName = '/chat';

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};

  // --- ADDED: Instance of CryptoService ---
  final CryptoService _cryptoService = CryptoService();
  final CacheService _cacheService = CacheService();

  List<Message> _messages = [];
  bool _isLoadingMessages = true;
  bool _isUploadingFile = false;
  String? _errorMessage;
  String? _highlightedMessageId;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _activeUsersSubscription;
  StreamSubscription? _conversationUpdateSubscription;
  StreamSubscription? _messageStatusUpdateSubscription;
  StreamSubscription? _messageUpdateSubscription;

  Message? _replyingToMessage;

  User? _currentUser;
  late Conversation _currentConversation;

  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _audioPath;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<Message> _searchResults = [];
  int _currentSearchIndex = 0;
  bool _isSearchLoading = false;

  int _currentPage = 1;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;

  bool _isOtherUserTyping = false;
  // bool _isTargetUserOnline = false;
  Timer? _typingTimer;
  String? _downloadingFileId;
  bool _isLeavingGroup = false;
  final Map<String, bool> _isManagingMemberMap = {};

  final TextEditingController _editGroupNameController =
      TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  String get appBarTitle {
    if (_currentConversation.isGroupChat) {
      return _currentConversation.groupName ?? 'Group Chat';
    }
    return widget.otherUser.id.isNotEmpty ? widget.otherUser.fullName : "Chat";
  }

  String? get appBarAvatarUrl {
    if (_currentConversation.isGroupChat) {
      return _currentConversation.groupPictureUrl;
    }
    return widget.otherUser.id.isNotEmpty
        ? widget.otherUser.profilePictureUrl
        : null;
  }

  bool get isGroupChat {
    return _currentConversation.isGroupChat;
  }

  bool get isCurrentUserAdmin {
    if (_currentUser == null || _currentConversation.groupAdmins == null) {
      return false;
    }
    return _currentConversation.isGroupChat &&
        _currentConversation.groupAdmins!.any(
          (admin) => admin.id == _currentUser!.id,
        );
  }

  @override
  void initState() {
    super.initState();
    _currentUser = authService.currentUser;
    _currentConversation = widget.conversation;
    _editGroupNameController.text = _currentConversation.groupName ?? "";
    _scrollController.addListener(_scrollListener);

    if (_currentUser == null) {
      _handleInvalidSession();
      return;
    }

    _messageController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    _messageUpdateSubscription = socketService.messageUpdateStream.listen((
      updatedMessage,
    ) {
      if (mounted) {
        final index = _messages.indexWhere((m) => m.id == updatedMessage.id);
        if (index != -1) {
          setState(() {
            _messages[index] = updatedMessage;
          });
        }
      }
    });

    _markConversationAsRead();

    _loadInitialMessages();
    socketService.joinConversation(_currentConversation.id);
    _subscribeToSocketEvents();
    // _checkInitialOnlineStatus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markVisibleMessagesAsRead();
    });
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
            _scrollController.position.minScrollExtent &&
        !_isLoadingMore) {
      _fetchMoreMessagesFromServer();
    }
  }

  void _markConversationAsRead() {
    chatService.markAsRead(widget.conversation.id).catchError((e) {
      print("ChatScreen: Background 'mark as read' failed: $e");
    });
  }

  void _handleInvalidSession() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Error: User session invalid. Please re-login."),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  void _subscribeToSocketEvents() {
    _messageSubscription = socketService.messageStream.listen((message) async {
      if (message.conversationId == _currentConversation.id && mounted) {
        Message messageToShow = message;
        if (message.isEncrypted) {
          await _cryptoService.ready;
          String? decryptedContent;

          if (isGroupChat) {
            decryptedContent = await _cryptoService.decryptGroupMessage(
              message.conversationId,
              message.content,
            );
          } else {
            decryptedContent = await _cryptoService.decrypt1on1Message(
              widget.otherUser.id,
              message.content,
            );
          }
          messageToShow = message.copyWith(
            content: decryptedContent ?? '[❌ Decryption Failed]',
          );
        }

        // --- ADDED: Save incoming message to cache ---
        await _cacheService.addOrUpdateMessage(messageToShow);

        if (mounted) {
          setState(() {
            _messages.add(messageToShow);
          });
          _scrollToBottom();
          // --- Mark as read if the incoming message is from another user ---
          if (message.sender?.id != _currentUser?.id) {
            socketService.markMessagesAsRead(_currentConversation.id);
          }
        }
      }
    });

    _messageUpdateSubscription = socketService.messageUpdateStream.listen((
      updatedMessage,
    ) async {
      if (mounted) {
        final index = _messages.indexWhere((m) => m.id == updatedMessage.id);
        if (index != -1) {
          Message messageToUpdate = updatedMessage;
          if (updatedMessage.isEncrypted) {
            await _cryptoService.ready;
            String? decryptedContent;
            if (isGroupChat) {
              decryptedContent = await _cryptoService.decryptGroupMessage(
                updatedMessage.conversationId,
                updatedMessage.content,
              );
            } else {
              decryptedContent = await _cryptoService.decrypt1on1Message(
                widget.otherUser.id,
                updatedMessage.content,
              );
            }
            messageToUpdate = updatedMessage.copyWith(
              content: decryptedContent ?? '[❌ Decryption Failed]',
            );
          }

          // --- ADDED: Update message in cache ---
          await _cacheService.addOrUpdateMessage(messageToUpdate);

          setState(() {
            _messages[index] = messageToUpdate;
          });
        }
      }
    });

    _messageStatusUpdateSubscription = socketService.messageStatusUpdateStream
        .listen((update) {
          if (update['conversationId'] == _currentConversation.id && mounted) {
            setState(() {
              if (update['status'] == 'read') {
                for (var i = 0; i < _messages.length; i++) {
                  if (_messages[i].sender?.id == _currentUser?.id &&
                      _messages[i].status != 'read') {
                    _messages[i] = _messages[i].copyWith(status: 'read');
                  }
                }
              } else if (update['status'] == 'delivered') {
                final messageId = update['messageId'];
                final messageIndex = _messages.indexWhere(
                  (m) => m.id == messageId,
                );
                if (messageIndex != -1 &&
                    _messages[messageIndex].status == 'sent') {
                  _messages[messageIndex] = _messages[messageIndex].copyWith(
                    status: 'delivered',
                  );
                }
              }
            });
          }
        });

    _conversationUpdateSubscription = socketService.conversationUpdateStream
        .listen((updatedConv) {
          if (updatedConv.id == _currentConversation.id && mounted) {
            setState(() {
              _currentConversation = updatedConv;
              _editGroupNameController.text =
                  _currentConversation.groupName ?? "";
            });
          }
        });

    if (!isGroupChat && widget.otherUser.id.isNotEmpty) {
      _typingSubscription = socketService.typingStatusStream.listen((status) {
        if (status['conversationId'] == _currentConversation.id &&
            status['userId'] == widget.otherUser.id &&
            mounted) {
          setState(() {
            _isOtherUserTyping = status['isTyping'] as bool? ?? false;
          });
        }
      });
    }
  }

  void _checkInitialOnlineStatus() {}

  void _showMessageOptions(BuildContext context, Message message) {
    if (message.sender == null ||
        message.sender!.id != _currentUser?.id ||
        message.deletedAt != null) {
      return;
    }

    final bool isMyMessage = message.sender?.id == _currentUser?.id;

    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _replyingToMessage = message;
                  });
                },
              ),
              if (isMyMessage)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showEditDialog(message);
                  },
                ),
              if (isMyMessage)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showDeleteConfirmation(message);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showEditDialog(Message message) {
    final controller = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Edit Message'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLines: null,
            ),
            actions: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              TextButton(
                child: const Text('Save'),
                onPressed: () async {
                  try {
                    final updatedMessage = await chatService.editMessage(
                      message.id,
                      controller.text,
                    );
                    setState(() {
                      final index = _messages.indexWhere(
                        (m) => m.id == updatedMessage.id,
                      );
                      if (index != -1) {
                        _messages[index] = updatedMessage;
                      }
                    });
                  } catch (e) {
                    // handle error
                  }
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
    );
  }

  void _showDeleteConfirmation(Message message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Message?'),
            content: const Text(
              'This message will be permanently deleted for everyone.',
            ),
            actions: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              TextButton(
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
                onPressed: () async {
                  try {
                    final updatedMessage = await chatService.deleteMessage(
                      message.id,
                    );
                    setState(() {
                      final index = _messages.indexWhere(
                        (m) => m.id == updatedMessage.id,
                      );
                      if (index != -1) {
                        _messages[index] = updatedMessage;
                      }
                    });
                  } catch (e) {
                    // handle error
                  }
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _editGroupNameController.dispose();
    _audioRecorder.dispose();
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _activeUsersSubscription?.cancel();
    _conversationUpdateSubscription?.cancel();
    _messageStatusUpdateSubscription?.cancel();
    _messageUpdateSubscription?.cancel();
    _typingTimer?.cancel();
    if (socketService.socket != null && socketService.socket!.connected) {
      socketService.leaveConversation(_currentConversation.id);
    }
    super.dispose();
  }

  void _markVisibleMessagesAsRead() {
    if (isGroupChat) return;

    final bool hasUnreadMessages = _messages.any(
      (m) => m.sender?.id == widget.otherUser.id && m.status != 'read',
    );

    if (hasUnreadMessages) {
      socketService.markMessagesAsRead(_currentConversation.id);
    }
  }

  // --- NEW: Cache-then-network strategy for messages ---
  Future<void> _loadInitialMessages() async {
    setState(() {
      _isLoadingMessages = true;
      _errorMessage = null;
    });

    // 1. Load from cache
    final cachedMessages = _cacheService.getMessages(_currentConversation.id);
    if (cachedMessages.isNotEmpty) {
      setState(() {
        _messages = cachedMessages;
        _isLoadingMessages = false;
      });
      _scrollToBottom();
    }

    // 2. Fetch from network
    await _fetchMessagesFromServer();
  }

  Future<void> _fetchMessagesFromServer() async {
    try {
      final messagesFromServer = await chatService.getMessages(
        _currentConversation.id,
      );
      final decryptedMessages = await _decryptMessageList(messagesFromServer);

      await _cacheService.saveMessages(
        _currentConversation.id,
        decryptedMessages,
      );

      if (mounted) {
        setState(() {
          _messages = decryptedMessages;
          _isLoadingMessages = false;
        });
        _scrollToBottom();
        socketService.markMessagesAsRead(_currentConversation.id);
      }
    } catch (e) {
      if (mounted && _messages.isEmpty) {
        setState(() {
          _errorMessage =
              "Failed to load messages: ${e.toString().replaceFirst("Exception: ", "")}";
          _isLoadingMessages = false;
        });
      }
    }
  }

  Future<void> _fetchMoreMessagesFromServer() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);
    _currentPage++;

    try {
      final newMessagesFromServer = await chatService.getMessages(
        _currentConversation.id,
        page: _currentPage,
      );

      if (newMessagesFromServer.isEmpty) {
        if (mounted) setState(() => _hasMoreMessages = false);
      } else {
        final decryptedNewMessages = await _decryptMessageList(
          newMessagesFromServer,
        );

        await _cacheService.saveMessages(
          _currentConversation.id,
          decryptedNewMessages,
        );

        if (mounted) {
          setState(() {
            _messages.insertAll(0, decryptedNewMessages);
          });
        }
      }
    } catch (e) {
      print("Failed to load more messages: $e");
      _currentPage--;
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  // --- NEW: Helper function to decrypt a list of messages ---
  Future<List<Message>> _decryptMessageList(List<Message> messages) async {
    await _cryptoService.ready;
    return Future.wait(
      messages.map((message) async {
        if (message.isEncrypted) {
          String? decryptedContent;
          if (isGroupChat) {
            decryptedContent = await _cryptoService.decryptGroupMessage(
              message.conversationId,
              message.content,
            );
          } else {
            decryptedContent = await _cryptoService.decrypt1on1Message(
              widget.otherUser.id,
              message.content,
            );
          }
          return message.copyWith(
            content: decryptedContent ?? '[❌ Decryption Failed]',
          );
        } else {
          return message;
        }
      }),
    );
  }

  // --- This function now handles decryption for fetched messages ---
  Future<void> _fetchMessages() async {
    if (!mounted) return;
    setState(() {
      _isLoadingMessages = true;
      _errorMessage = null;
      _currentPage = 1;
      _hasMoreMessages = true;
    });

    try {
      final messagesFromServer = await chatService.getMessages(
        _currentConversation.id,
      );
      await _cryptoService.ready;

      final decryptedMessages = await Future.wait(
        messagesFromServer.map((message) async {
          if (message.isEncrypted) {
            String? decryptedContent;
            if (isGroupChat) {
              decryptedContent = await _cryptoService.decryptGroupMessage(
                message.conversationId,
                message.content,
              );
            } else {
              decryptedContent = await _cryptoService.decrypt1on1Message(
                widget.otherUser.id,
                message.content,
              );
            }
            return message.copyWith(
              content: decryptedContent ?? '[❌ Decryption Failed]',
            );
          } else {
            return message;
          }
        }),
      );

      if (mounted) {
        setState(() {
          _messages = decryptedMessages;
          _isLoadingMessages = false;
        });

        socketService.markMessagesAsRead(_currentConversation.id);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              "Failed to load messages: ${e.toString().replaceFirst("Exception: ", "")}";
          _isLoadingMessages = false;
        });
      }
      print("ChatScreen: Error fetching messages: $e");
    }
  }

  // --- CORRECTED: This function also now handles decryption for paginated messages ---
  Future<void> _fetchMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);
    _currentPage++;

    try {
      final newMessagesFromServer = await chatService.getMessages(
        _currentConversation.id,
        page: _currentPage,
      );

      if (newMessagesFromServer.isEmpty) {
        if (mounted) setState(() => _hasMoreMessages = false);
      } else {
        await _cryptoService.ready;

        final decryptedNewMessages = await Future.wait(
          newMessagesFromServer.map((message) async {
            if (message.isEncrypted) {
              String? decryptedContent;
              if (isGroupChat) {
                decryptedContent = await _cryptoService.decryptGroupMessage(
                  message.conversationId,
                  message.content,
                );
              } else {
                decryptedContent = await _cryptoService.decrypt1on1Message(
                  widget.otherUser.id,
                  message.content,
                );
              }
              return message.copyWith(
                content: decryptedContent ?? '[❌ Decryption Failed]',
              );
            } else {
              return message;
            }
          }),
        );

        if (mounted) {
          setState(() {
            _messages.insertAll(0, decryptedNewMessages);
          });
        }
      }
    } catch (e) {
      print("Failed to load more messages: $e");
      _currentPage--;
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  // --- Handles encryption for both 1-to-1 and group chats ---
  void _sendMessage() {
    final String text = _messageController.text.trim();
    if (text.isEmpty || _currentUser == null) return;

    String? recipientId;
    // For 1-to-1 chats, we need the recipient's ID. For groups, it's null.
    if (!isGroupChat) {
      try {
        final otherParticipant = _currentConversation.participants.firstWhere(
          (p) => p.id != _currentUser!.id,
        );
        recipientId = otherParticipant.id;
      } catch (e) {
        print("❌ FAILED: Could not find other participant. Error: $e");
        return; // Don't send if recipient can't be found
      }
    }

    socketService.sendMessage(
      conversationId: _currentConversation.id,
      senderId: _currentUser!.id,
      content: text,
      recipientId: recipientId, // Null for group chats
      isEncrypted: true, // Encrypt all text messages by default now
      replyTo: _replyingToMessage?.id,
      replySnippet: _replyingToMessage?.content,
      replySenderName: _replyingToMessage?.sender?.fullName,
    );

    _messageController.clear();
    if (!isGroupChat) _emitStopTyping();
    _scrollToBottom();

    if (_replyingToMessage != null) {
      setState(() {
        _replyingToMessage = null;
      });
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'pdf',
          'doc',
          'docx',
          'mp4',
          'mov',
        ],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);

        final String? caption = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (context) => FilePreviewScreen(file: file),
          ),
        );

        if (caption == null) return;

        setState(() => _isUploadingFile = true);

        final fileData = await chatService.uploadChatFile(file);

        socketService.sendMessage(
          conversationId: _currentConversation.id,
          senderId: _currentUser!.id,
          content: caption,
          fileUrl: fileData['fileUrl'],
          fileType: fileData['fileType'],
          fileName: fileData['fileName'],
          isEncrypted: false,
          replyTo: _replyingToMessage?.id,
          replySnippet: _replyingToMessage?.content,
          replySenderName: _replyingToMessage?.sender?.fullName,
        );

        if (_replyingToMessage != null) {
          setState(() {
            _replyingToMessage = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingFile = false);
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final filePath = p.join(
          tempDir.path,
          'voice_message_${DateTime.now().millisecondsSinceEpoch}.m4a',
        );

        await _audioRecorder.start(const RecordConfig(), path: filePath);

        setState(() {
          _isRecording = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Microphone permission not granted.")),
        );
      }
    } catch (e) {
      print("DEBUG: Error starting recording: $e");
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchResults = [];
        _currentSearchIndex = 0;
        _highlightedMessageId = null;
      }
    });
  }

  Future<void> _executeSearch() async {
    if (_searchController.text.isEmpty) return;

    setState(() {
      _isSearchLoading = true;
      _highlightedMessageId = null;
    });

    try {
      final results = await chatService.searchMessages(
        _currentConversation.id,
        _searchController.text,
      );
      setState(() {
        _searchResults = results;
        _currentSearchIndex = 0;
        if (results.isNotEmpty) {
          _scrollToRepliedMessage(results.first.id);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("No messages found.")));
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Search failed: $e")));
    } finally {
      if (mounted) {
        setState(() => _isSearchLoading = false);
      }
    }
  }

  void _navigateToSearchResult(int direction) {
    if (_searchResults.isEmpty) return;

    setState(() {
      _currentSearchIndex =
          (_currentSearchIndex + direction) % _searchResults.length;
      if (_currentSearchIndex < 0) {
        _currentSearchIndex = _searchResults.length - 1;
      }
      _scrollToRepliedMessage(_searchResults[_currentSearchIndex].id);
    });
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (path == null) return;

      setState(() {
        _isRecording = false;
        _audioPath = path;
      });

      File file = File(path);
      setState(() => _isUploadingFile = true);

      final fileData = await chatService.uploadChatFile(file);

      socketService.sendMessage(
        conversationId: _currentConversation.id,
        senderId: _currentUser!.id,
        content: '',
        fileUrl: fileData['fileUrl'],
        fileType: fileData['fileType'],
        fileName: fileData['fileName'],
        isEncrypted: false,
      );
    } catch (e) {
      print("Error stopping recording: $e");
    } finally {
      if (mounted) setState(() => _isUploadingFile = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTypingChanged(String text) {
    if (_currentUser == null || isGroupChat) return;
    if (text.isNotEmpty) {
      _typingTimer?.cancel();
      socketService.emitTyping(
        _currentConversation.id,
        _currentUser!.id,
        _currentUser!.fullName,
      );
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _emitStopTyping();
      });
    } else {
      _emitStopTyping();
    }
  }

  void _emitStopTyping() {
    if (_currentUser == null || isGroupChat) return;
    _typingTimer?.cancel();
    socketService.emitStopTyping(
      _currentConversation.id,
      _currentUser!.id,
      _currentUser!.fullName,
    );
  }

  Future<void> _changeGroupPicture(
    BuildContext dialogContext,
    StateSetter setDialogState,
  ) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (pickedFile == null || !mounted) return;

      setDialogState(() {});

      final updatedConversation = await chatService.uploadGroupPicture(
        conversationId: _currentConversation.id,
        imageFile: File(pickedFile.path),
      );

      if (mounted) {
        setState(() {
          _currentConversation = updatedConversation;
        });
        setDialogState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group picture updated!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update group picture: ${e.toString().replaceFirst("Exception: ", "")}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setDialogState(() {});
      }
    }
  }

  void _showEditGroupNameDialog(
    BuildContext parentDialogContext,
    StateSetter setParentDialogState,
  ) {
    _editGroupNameController.text = _currentConversation.groupName ?? "";
    showDialog(
      context: context,
      builder: (BuildContext editNameDialogCtx) {
        bool isSavingName = false;
        return StatefulBuilder(
          builder: (context, setDialogSaveState) {
            return AlertDialog(
              title: const Text("Edit Group Name"),
              content: TextField(
                controller: _editGroupNameController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: "Enter new group name",
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(editNameDialogCtx).pop(),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed:
                      isSavingName
                          ? null
                          : () async {
                            final newName =
                                _editGroupNameController.text.trim();
                            if (newName.isNotEmpty &&
                                newName != _currentConversation.groupName) {
                              setDialogSaveState(() => isSavingName = true);
                              await _handleUpdateGroupName(
                                newName,
                                setParentDialogState,
                              );
                              if (mounted)
                                Navigator.of(editNameDialogCtx).pop();
                            } else if (newName.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Group name cannot be empty."),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            } else {
                              Navigator.of(editNameDialogCtx).pop();
                            }
                          },
                  child:
                      isSavingName
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'last seen a long time ago';

    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'last seen just now';
    } else if (difference.inHours < 1) {
      return 'last seen ${difference.inMinutes} minutes ago';
    } else if (DateUtils.isSameDay(now, lastSeen)) {
      return 'last seen today at ${DateFormat.jm().format(lastSeen)}';
    } else if (DateUtils.isSameDay(
      now.subtract(const Duration(days: 1)),
      lastSeen,
    )) {
      return 'last seen yesterday at ${DateFormat.jm().format(lastSeen)}';
    } else {
      return 'last seen on ${DateFormat.yMd().format(lastSeen)}';
    }
  }

  void _scrollToRepliedMessage(String? repliedMessageId) {
    if (repliedMessageId == null) return;

    final targetKey = _messageKeys[repliedMessageId];
    final targetContext = targetKey?.currentContext;

    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
      _highlightRepliedMessage(repliedMessageId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Original message not currently loaded."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _highlightRepliedMessage(String messageId) {
    setState(() {
      _highlightedMessageId = messageId;
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  Future<void> _handleUpdateGroupName(
    String newName,
    StateSetter setParentDialogState,
  ) async {
    try {
      final updatedConversation = await chatService.updateGroupName(
        conversationId: _currentConversation.id,
        newName: newName,
      );
      if (mounted) {
        setState(() {
          _currentConversation = updatedConversation;
        });
        setParentDialogState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group name updated!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update group name: ${e.toString().replaceFirst("Exception: ", "")}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- Handles sharing the group key with new members ---
  void _showGroupMembers(BuildContext context) {
    if (!_currentConversation.isGroupChat) return;
    _editGroupNameController.text = _currentConversation.groupName ?? "";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            final bool amIAdminNow =
                _currentConversation.isGroupChat &&
                _currentConversation.groupAdmins?.any(
                      (admin) => admin.id == _currentUser?.id,
                    ) ==
                    true;

            return AlertDialog(
              titlePadding: const EdgeInsets.all(0),
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
                    child: Row(
                      children: [
                        UserAvatar(
                          imageUrl: _currentConversation.groupPictureUrl,
                          userName: _currentConversation.groupName ?? "G",
                          radius: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _currentConversation.groupName ?? "Group Details",
                            style: Theme.of(context).textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (amIAdminNow)
                          IconButton(
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: Colors.grey[700],
                            ),
                            tooltip: "Edit Group Name",
                            onPressed:
                                () => _showEditGroupNameDialog(
                                  dialogContext,
                                  setDialogState,
                                ),
                          ),
                        if (amIAdminNow)
                          IconButton(
                            icon: Icon(
                              Icons.photo_camera_outlined,
                              size: 20,
                              color: Colors.grey[700],
                            ),
                            tooltip: "Change Group Picture",
                            onPressed:
                                () => _changeGroupPicture(
                                  dialogContext,
                                  setDialogState,
                                ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 12, thickness: 0.8),
                ],
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
              contentPadding: const EdgeInsets.only(top: 0.0),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.50,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (amIAdminNow)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(
                              Icons.person_add_alt_1_outlined,
                              size: 18,
                            ),
                            label: const Text(
                              "Add Members",
                              style: TextStyle(fontSize: 14),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () async {
                              final List<String> originalMemberIds =
                                  _currentConversation.participants
                                      .map((p) => p.id)
                                      .toList();

                              final Conversation? updatedConvData =
                                  await Navigator.of(
                                    context,
                                  ).push<Conversation>(
                                    MaterialPageRoute(
                                      builder:
                                          (_) => AddMembersToGroupScreen(
                                            currentGroup: _currentConversation,
                                          ),
                                    ),
                                  );

                              if (updatedConvData != null && mounted) {
                                setState(() {
                                  _currentConversation = updatedConvData;
                                });
                                setDialogState(() {});

                                // --- KEY SHARING LOGIC ---
                                final List<String> newMemberIds =
                                    updatedConvData.participants
                                        .map((p) => p.id)
                                        .where(
                                          (id) =>
                                              !originalMemberIds.contains(id),
                                        )
                                        .toList();

                                if (newMemberIds.isNotEmpty) {
                                  print(
                                    "Sharing group key with ${newMemberIds.length} new members.",
                                  );
                                  for (final memberId in newMemberIds) {
                                    socketService.shareGroupKey(
                                      _currentConversation.id,
                                      memberId,
                                    );
                                  }
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16.0,
                        amIAdminNow ? 4.0 : 12.0,
                        16.0,
                        8.0,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "${_currentConversation.participants.length} Members",
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: Colors.grey[700]),
                        ),
                      ),
                    ),
                    const Divider(height: 1, thickness: 0.7),
                    Expanded(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _currentConversation.participants.length,
                        separatorBuilder:
                            (context, index) => Divider(
                              height: 1,
                              indent: 72,
                              endIndent: 16,
                              color: Colors.grey[200],
                            ),
                        itemBuilder: (context, index) {
                          final member =
                              _currentConversation.participants[index];
                          final bool isMemberAdmin =
                              _currentConversation.groupAdmins?.any(
                                (admin) => admin.id == member.id,
                              ) ??
                              false;
                          final bool isSelf = member.id == _currentUser?.id;
                          final bool isCurrentlyBeingManaged =
                              _isManagingMemberMap[member.id] ?? false;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            leading: UserAvatar(
                              imageUrl: member.profilePictureUrl,
                              userName: member.fullName,
                              radius: 22,
                            ),
                            title: Text(
                              member.fullName,
                              style: TextStyle(
                                fontWeight:
                                    isSelf
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                              ),
                            ),
                            subtitle:
                                isMemberAdmin
                                    ? Text(
                                      "Admin",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).primaryColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    )
                                    : null,
                            trailing:
                                amIAdminNow && !isSelf
                                    ? (isCurrentlyBeingManaged
                                        ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                        : PopupMenuButton<String>(
                                          icon: Icon(
                                            Icons.more_vert_rounded,
                                            color: Colors.grey[600],
                                          ),
                                          tooltip:
                                              "Member Actions for ${member.fullName.split(' ').first}",
                                          onSelected: (String action) {
                                            if (action == 'remove') {
                                              _confirmRemoveMember(
                                                dialogContext,
                                                member,
                                                setDialogState,
                                              );
                                            } else if (action == 'make_admin') {
                                              _confirmPromoteToAdmin(
                                                dialogContext,
                                                member,
                                                setDialogState,
                                              );
                                            } else if (action ==
                                                'demote_admin') {
                                              _confirmDemoteAdmin(
                                                dialogContext,
                                                member,
                                                setDialogState,
                                              );
                                            }
                                          },
                                          itemBuilder:
                                              (
                                                BuildContext context,
                                              ) => <PopupMenuEntry<String>>[
                                                if (!isMemberAdmin)
                                                  const PopupMenuItem<String>(
                                                    value: 'make_admin',
                                                    child: ListTile(
                                                      leading: Icon(
                                                        Icons
                                                            .admin_panel_settings_outlined,
                                                      ),
                                                      title: Text('Make Admin'),
                                                    ),
                                                  ),
                                                if (isMemberAdmin &&
                                                    (_currentConversation
                                                                .groupAdmins
                                                                ?.length ??
                                                            0) >
                                                        1)
                                                  const PopupMenuItem<String>(
                                                    value: 'demote_admin',
                                                    child: ListTile(
                                                      leading: Icon(
                                                        Icons
                                                            .no_accounts_outlined,
                                                        color: Colors.orange,
                                                      ),
                                                      title: Text(
                                                        'Demote Admin',
                                                        style: TextStyle(
                                                          color: Colors.orange,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                const PopupMenuDivider(),
                                                PopupMenuItem<String>(
                                                  value: 'remove',
                                                  child: ListTile(
                                                    leading: Icon(
                                                      Icons
                                                          .person_remove_outlined,
                                                      color:
                                                          Theme.of(
                                                            context,
                                                          ).colorScheme.error,
                                                    ),
                                                    title: Text(
                                                      'Remove User',
                                                      style: TextStyle(
                                                        color:
                                                            Theme.of(
                                                              context,
                                                            ).colorScheme.error,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                        ))
                                    : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                if (_currentConversation.participants.any(
                  (p) => p.id == _currentUser?.id,
                ))
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    child:
                        _isLeavingGroup
                            ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Text('Leave Group'),
                    onPressed:
                        _isLeavingGroup
                            ? null
                            : () {
                              Navigator.of(dialogContext).pop();
                              _confirmLeaveGroup();
                            },
                  ),
                TextButton(
                  child: const Text('Close'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _confirmRemoveMember(
    BuildContext parentDialogContext,
    User memberToRemove,
    StateSetter setDialogStateInParent,
  ) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext confirmDialogCtx) => AlertDialog(
            title: Text('Remove ${memberToRemove.fullName.split(" ").first}?'),
            content: Text(
              'Are you sure you want to remove ${memberToRemove.fullName} from this group?',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(confirmDialogCtx).pop(false),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Remove'),
                onPressed: () => Navigator.of(confirmDialogCtx).pop(true),
              ),
            ],
          ),
    );
    if (confirm == true) {
      setDialogStateInParent(() {
        _isManagingMemberMap[memberToRemove.id] = true;
      });
      try {
        final updatedConversation = await chatService.removeMemberFromGroup(
          conversationId: _currentConversation.id,
          userIdToRemove: memberToRemove.id,
        );
        if (mounted) {
          setState(() {
            _currentConversation = updatedConversation;
          });
          setDialogStateInParent(() {
            _isManagingMemberMap.remove(memberToRemove.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${memberToRemove.fullName} removed successfully.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to remove member: ${e.toString().replaceFirst("Exception: ", "")}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setDialogStateInParent(() {
            _isManagingMemberMap.remove(memberToRemove.id);
          });
        }
      }
    }
  }

  Future<void> _confirmPromoteToAdmin(
    BuildContext parentDialogContext,
    User memberToPromote,
    StateSetter setDialogStateInParent,
  ) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext confirmDialogCtx) => AlertDialog(
            title: Text(
              'Make ${memberToPromote.fullName.split(" ").first} Admin?',
            ),
            content: Text(
              'Are you sure you want to make ${memberToPromote.fullName} an admin of this group?',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(confirmDialogCtx).pop(false),
              ),
              TextButton(
                child: const Text(
                  'Make Admin',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () => Navigator.of(confirmDialogCtx).pop(true),
              ),
            ],
          ),
    );
    if (confirm == true) {
      setDialogStateInParent(() {
        _isManagingMemberMap[memberToPromote.id] = true;
      });
      try {
        final updatedConversation = await chatService.promoteToAdmin(
          conversationId: _currentConversation.id,
          userIdToPromote: memberToPromote.id,
        );
        if (mounted) {
          setState(() {
            _currentConversation = updatedConversation;
          });
          setDialogStateInParent(() {
            _isManagingMemberMap.remove(memberToPromote.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${memberToPromote.fullName} is now an admin.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to promote to admin: ${e.toString().replaceFirst("Exception: ", "")}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setDialogStateInParent(() {
            _isManagingMemberMap.remove(memberToPromote.id);
          });
        }
      }
    }
  }

  Future<void> _confirmDemoteAdmin(
    BuildContext parentDialogContext,
    User adminToDemote,
    StateSetter setDialogStateInParent,
  ) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext confirmDialogCtx) => AlertDialog(
            title: Text('Demote ${adminToDemote.fullName.split(" ").first}?'),
            content: Text(
              'Are you sure you want to remove admin rights for ${adminToDemote.fullName}? They will remain a member.',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(confirmDialogCtx).pop(false),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Demote'),
                onPressed: () => Navigator.of(confirmDialogCtx).pop(true),
              ),
            ],
          ),
    );
    if (confirm == true) {
      setDialogStateInParent(() {
        _isManagingMemberMap[adminToDemote.id] = true;
      });
      try {
        final updatedConversation = await chatService.demoteAdmin(
          conversationId: _currentConversation.id,
          userIdToDemote: adminToDemote.id,
        );
        if (mounted) {
          setState(() {
            _currentConversation = updatedConversation;
          });
          setDialogStateInParent(() {
            _isManagingMemberMap.remove(adminToDemote.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${adminToDemote.fullName} is no longer an admin.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to demote admin: ${e.toString().replaceFirst("Exception: ", "")}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setDialogStateInParent(() {
            _isManagingMemberMap.remove(adminToDemote.id);
          });
        }
      }
    }
  }

  void _showOtherUserDetails(BuildContext context) {
    if (_currentConversation.isGroupChat || widget.otherUser.id.isEmpty) return;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StreamBuilder<List<String>>(
          stream: socketService.activeUsersStream,
          initialData: socketService.lastActiveUsers,
          builder: (context, snapshot) {
            final activeUserIds = snapshot.data ?? [];
            final isUserOnline = activeUserIds.contains(widget.otherUser.id);

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
              titlePadding: const EdgeInsets.all(0),
              title: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0, bottom: 10),
                    child: Center(
                      child: UserAvatar(
                        imageUrl: widget.otherUser.profilePictureUrl,
                        userName: widget.otherUser.fullName,
                        radius: 45,
                        isActive: isUserOnline,
                        borderWidth: 2.5,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      tooltip: "Close",
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      widget.otherUser.fullName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.otherUser.email,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 12,
                          color:
                              isUserOnline
                                  ? Colors.greenAccent[700]
                                  : Colors.grey[400],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isUserOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                isUserOnline
                                    ? Colors.greenAccent[700]
                                    : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: <Widget>[
                TextButton(
                  child: const Text('OK', style: TextStyle(fontSize: 16)),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmLeaveGroup() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Leave Group?'),
            content: Text(
              'Are you sure you want to leave "${_currentConversation.groupName ?? "this group"}"?',
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Leave'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
    );
    if (confirm == true) {
      if (!mounted) return;
      setState(() {
        _isLeavingGroup = true;
      });
      try {
        final result = await chatService.leaveGroup(_currentConversation.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Successfully left group.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (Route<dynamic> route) => route.isFirst,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to leave group: ${e.toString().replaceFirst("Exception: ", "")}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLeavingGroup = false;
          });
        }
      }
    }
  }

  bool _shouldShowDateSeparator(int currentIndex) {
    if (currentIndex == 0) {
      return true;
    }
    final previousMessage = _messages[currentIndex - 1];
    final currentMessage = _messages[currentIndex];
    final previousDate = DateUtils.dateOnly(
      previousMessage.createdAt.toLocal(),
    );
    final currentDate = DateUtils.dateOnly(currentMessage.createdAt.toLocal());
    return !DateUtils.isSameDay(previousDate, currentDate);
  }

  bool _isConsecutiveMessage(int currentIndex) {
    if (currentIndex == 0) return false;
    final previousMessage = _messages[currentIndex - 1];
    final currentMessage = _messages[currentIndex];

    if (previousMessage.sender == null || currentMessage.sender == null) {
      return false;
    }

    return previousMessage.sender!.id == currentMessage.sender!.id &&
        currentMessage.createdAt
                .difference(previousMessage.createdAt)
                .inMinutes <
            1;
  }

  Widget _buildReplyPreview() {
    final messageToReplyTo = _replyingToMessage!;
    final bool isReplyingToSelf =
        messageToReplyTo.sender?.id == _currentUser?.id;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.08),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
        border: Border(
          left: BorderSide(color: Theme.of(context).primaryColor, width: 4),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isReplyingToSelf
                      ? 'You'
                      : (messageToReplyTo.sender?.fullName ?? 'User'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  (messageToReplyTo.fileUrl != null &&
                          messageToReplyTo.fileUrl!.isNotEmpty)
                      ? "📄 ${messageToReplyTo.fileName ?? "File"}"
                      : messageToReplyTo.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              setState(() {
                _replyingToMessage = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(Message message, bool isConsecutive) {
    final bool isMe = message.sender?.id == _currentUser?.id;
    final bool isDeleted = message.deletedAt != null;
    final bool isHighlighted = _highlightedMessageId == message.id;

    Widget messageContent = _buildTextBubble(
      message,
      isMe,
      BorderRadius.circular(18.0),
    );
    if (message.fileUrl != null && message.fileUrl!.isNotEmpty) {
      messageContent = _buildFileBubble(
        message,
        isMe,
        BorderRadius.circular(18.0),
      );
    }

    Widget messageContainer = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: isHighlighted ? const EdgeInsets.all(4.0) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color:
            isHighlighted
                ? Theme.of(context).primaryColor.withOpacity(0.15)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      margin: EdgeInsets.only(
        top: isConsecutive ? 4.0 : 12.0,
        bottom: message.reactions.isNotEmpty ? 16.0 : 4.0,
        left: 16.0,
        right: 16.0,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe && !isConsecutive)
            UserAvatar(
              imageUrl: message.sender?.profilePictureUrl,
              userName: message.sender?.fullName ?? 'U',
              radius: 16,
            )
          else if (!isMe)
            const SizedBox(width: 32),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe && isGroupChat && !isConsecutive)
                  Padding(
                    padding: const EdgeInsets.only(left: 12.0, bottom: 4.0),
                    child: Text(
                      message.sender?.fullName.split(' ').first ?? 'User',
                      style: TextStyle(fontSize: 12.0, color: Colors.grey[600]),
                    ),
                  ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onLongPress: () {
                        if (!isDeleted) _showReactionPicker(context, message);
                      },
                      onDoubleTap: () {
                        if (!isDeleted) _showMessageOptions(context, message);
                      },
                      child: messageContent,
                    ),
                    if (message.reactions.isNotEmpty)
                      _buildReactionsDisplay(message, isMe),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Wrap the message container with Dismissible for swipe-to-reply
    return Dismissible(
      key: Key(message.id),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          setState(() {
            _replyingToMessage = message;
          });
        }
        return false; // This prevents the widget from being dismissed
      },
      background: Container(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerLeft,
        child: Icon(Icons.reply, color: Theme.of(context).primaryColor),
      ),
      child: messageContainer,
    );
  }

  Widget _buildReplyPreviewWidget(Message message, bool isMe) {
    return GestureDetector(
      onTap: () {
        _scrollToRepliedMessage(message.replyTo);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              isMe
                  ? Colors.white.withOpacity(0.2)
                  : Colors.black.withOpacity(0.05),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border(
            left: BorderSide(
              color:
                  isMe
                      ? Colors.lightBlue.shade200
                      : Theme.of(context).primaryColor,
              width: 4,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.replySenderName ?? "User",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color:
                    isMe
                        ? Colors.lightBlue.shade100
                        : Theme.of(context).primaryColor,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              (message.replySnippet != null && message.replySnippet!.isNotEmpty)
                  ? message.replySnippet!
                  : "📄 File",
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color:
                    isMe
                        ? const Color.fromARGB(
                          255,
                          247,
                          245,
                          245,
                        ).withOpacity(0.9)
                        : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextBubble(
    Message message,
    bool isMe,
    BorderRadius borderRadius,
  ) {
    final bool isDeleted = message.deletedAt != null;
    final bool isHighlighted = _highlightedMessageId == message.id;

    Widget _buildStatusIcon() {
      IconData iconData;
      Color iconColor;

      switch (message.status) {
        case 'read':
          iconData = Icons.done_all_rounded;
          iconColor = Colors.lightBlueAccent;
          break;
        case 'delivered':
          iconData = Icons.done_all_rounded;
          iconColor = Colors.white70;
          break;
        case 'sent':
        default:
          iconData = Icons.done_rounded;
          iconColor = Colors.white70;
          break;
      }
      return Icon(iconData, size: 16.0, color: iconColor);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color:
            isHighlighted
                ? Theme.of(context).primaryColorDark
                : (isMe
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).cardColor),
        borderRadius: borderRadius,
        border:
            isHighlighted
                ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                : null,
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(
              right: 70,
              bottom: message.isEdited ? 15.0 : 0.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.replyTo != null && !isDeleted)
                  _buildReplyPreviewWidget(message, isMe),
                Text(
                  isDeleted ? "This message was deleted" : message.content,
                  style: TextStyle(
                    color: isMe ? Colors.white : Colors.black87,
                    fontSize: 15.5,
                    height: 1.35,
                    fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Row(
              children: [
                if (message.isEdited && !isDeleted)
                  Text(
                    "edited",
                    style: TextStyle(
                      fontSize: 12,
                      color: isMe ? Colors.white70 : Colors.black54,
                    ),
                  ),
                const SizedBox(width: 4),
                Text(
                  _formatMessageTimestamp(message.createdAt),
                  style: TextStyle(
                    fontSize: 11.0,
                    color: isMe ? Colors.white70 : Colors.black54,
                  ),
                ),
                if (isMe && !isDeleted) ...[
                  const SizedBox(width: 5),
                  _buildStatusIcon(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileBubble(
    Message message,
    bool isMe,
    BorderRadius borderRadius,
  ) {
    final fileType = message.fileType ?? '';
    final isImage = fileType.startsWith('image/');
    final isPdf = fileType == 'application/pdf';
    final isAudio = fileType.startsWith('audio/');

    Widget fileContent;
    if (isImage) {
      fileContent = _buildImageContent(message, isMe);
    } else if (isAudio) {
      final fullAudioUrl = '$SERVER_ROOT_URL${message.fileUrl!}';
      fileContent = VoiceMessageBubble(audioUrl: fullAudioUrl, isMe: isMe);
    } else {
      fileContent = _buildGenericFileContent(message, isMe, isPdf);
    }

    return Container(
      width: MediaQuery.of(context).size.width * 0.65,
      decoration: BoxDecoration(
        color:
            isMe
                ? Theme.of(context).primaryColor.withAlpha(220)
                : Theme.of(context).cardColor,
        borderRadius: borderRadius,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: GestureDetector(
          onTap: () {
            final fullFileUrl = '$SERVER_ROOT_URL${message.fileUrl!}';

            if (isImage) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => PhotoViewerScreen(
                        imageUrl: fullFileUrl,
                        heroTag: message.id,
                      ),
                ),
              );
            } else if (isPdf) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => SyncfusionPdfViewerScreen(
                        fileUrl: fullFileUrl,
                        fileName: message.fileName ?? 'document.pdf',
                      ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("This file type can't be opened in the app."),
                ),
              );
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message.replyTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: _buildReplyPreviewWidget(message, isMe),
                ),
              fileContent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageContent(Message message, bool isMe) {
    final fullImageUrl = '$SERVER_ROOT_URL${message.fileUrl!}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Hero(
          tag: message.id,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(18.0),
            ),
            child: Image.network(
              fullImageUrl,
              height: 200,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return SizedBox(
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(
                      value:
                          progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                              : null,
                      color:
                          isMe ? Colors.white : Theme.of(context).primaryColor,
                    ),
                  ),
                );
              },
              errorBuilder:
                  (context, error, stack) => SizedBox(
                    height: 200,
                    child: Icon(
                      Icons.broken_image,
                      size: 50,
                      color: isMe ? Colors.white70 : Colors.grey,
                    ),
                  ),
            ),
          ),
        ),
        if (message.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Text(
              message.content,
              style: TextStyle(color: isMe ? Colors.white : Colors.black87),
            ),
          ),
      ],
    );
  }

  Widget _buildGenericFileContent(Message message, bool isMe, bool isPdf) {
    final bool isDownloading = _downloadingFileId == message.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (isDownloading)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color:
                          isMe ? Colors.white : Theme.of(context).primaryColor,
                    ),
                  ),
                )
              else
                Icon(
                  isPdf
                      ? Icons.picture_as_pdf_rounded
                      : Icons.insert_drive_file_outlined,
                  color:
                      isMe
                          ? Colors.white
                          : (isPdf
                              ? Colors.red.shade700
                              : Colors.grey.shade700),
                  size: 30,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message.fileName ?? 'File',
                  style: TextStyle(
                    color: isMe ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (message.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Text(
              message.content,
              style: TextStyle(color: isMe ? Colors.white : Colors.black87),
            ),
          ),
      ],
    );
  }

  String _formatMessageTimestamp(DateTime dateTime) {
    return DateFormat.jm().format(dateTime.toLocal());
  }

  Widget _DateSeparator(DateTime date) {
    String formattedDate;
    final now = DateUtils.dateOnly(DateTime.now());
    final yesterday = DateUtils.addDaysToDate(now, -1);

    if (DateUtils.isSameDay(date, now)) {
      formattedDate = 'Today';
    } else if (DateUtils.isSameDay(date, yesterday)) {
      formattedDate = 'Yesterday';
    } else if (now.year == date.year) {
      formattedDate = DateFormat('MMMM d').format(date);
    } else {
      formattedDate = DateFormat('yMMMMd').format(date);
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Text(
          formattedDate,
          style: TextStyle(
            fontSize: 12.0,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).primaryColorDark,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading:
            _isSearching
                ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close Search',
                  onPressed: _toggleSearch,
                )
                : null,
        leadingWidth: _isSearching ? 56 : null,
        titleSpacing: 0,
        title: _isSearching ? _buildSearchField() : _buildDefaultAppBarTitle(),
        actions: _isSearching ? _buildSearchActions() : _buildDefaultActions(),
      ),
      body: Column(
        children: [
          _buildConnectionStatusIndicator(),
          Expanded(
            child:
                _isLoadingMessages
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                    ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                    : _messages.isEmpty
                    ? const Center(child: Text("No messages yet. Say hello!"))
                    : ListView.builder(
                      controller: _scrollController,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final key = _messageKeys.putIfAbsent(
                          message.id,
                          () => GlobalKey(),
                        );

                        if (message.messageType == 'system') {
                          return _buildSystemMessage(message.content);
                        }

                        final isConsecutive = _isConsecutiveMessage(index);
                        final showDateSeparator = _shouldShowDateSeparator(
                          index,
                        );
                        final messageWidget = _buildMessageItem(
                          message,
                          isConsecutive,
                        );

                        return KeyedSubtree(
                          key: key,
                          child: Column(
                            children: [
                              if (showDateSeparator)
                                _DateSeparator(message.createdAt.toLocal()),
                              messageWidget,
                            ],
                          ),
                        );
                      },
                    ),
          ),
          if (_replyingToMessage != null) _buildReplyPreview(),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildDefaultAppBarTitle() {
    return StreamBuilder<List<String>>(
      stream: socketService.activeUsersStream,
      initialData: socketService.lastActiveUsers,
      builder: (context, snapshot) {
        final activeUserIds = snapshot.data ?? [];
        final isUserOnline = activeUserIds.contains(widget.otherUser.id);

        return GestureDetector(
          onTap:
              isGroupChat
                  ? () => _showGroupMembers(context)
                  : (widget.otherUser.id.isNotEmpty
                      ? () => _showOtherUserDetails(context)
                      : null),
          child: Row(
            children: [
              UserAvatar(
                imageUrl: appBarAvatarUrl,
                userName: appBarTitle,
                radius: 18,
                isActive: isGroupChat ? false : isUserOnline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      appBarTitle,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isGroupChat && _isOtherUserTyping)
                      const Text(
                        'typing...',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.white70,
                        ),
                      )
                    else if (!isGroupChat && isUserOnline)
                      const Text(
                        'Online',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      )
                    else if (!isGroupChat)
                      Text(
                        _formatLastSeen(widget.otherUser.lastSeen),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      )
                    else if (isGroupChat)
                      Text(
                        '${_currentConversation.participants.length} members',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConnectionStatusIndicator() {
    return StreamBuilder<SocketStatus>(
      stream: socketService.connectionStatusStream,
      initialData: socketService.lastStatus,
      builder: (context, snapshot) {
        // If the status is online, show nothing.
        if (snapshot.data == SocketStatus.online) {
          return const SizedBox.shrink();
        }

        // For any other status (connecting, offline), show the "Offline" banner.
        return Material(
          child: Container(
            width: double.infinity,
            color: Colors.grey[600]!, // Offline color
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, size: 14, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Offline. Check your connection.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildDefaultActions() {
    return [
      IconButton(
        icon: const Icon(Icons.search),
        tooltip: 'Search Messages',
        onPressed: _toggleSearch,
      ),
    ];
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      style: const TextStyle(color: Colors.white, fontSize: 17),
      cursorColor: Colors.white,
      decoration: const InputDecoration(
        hintText: 'Search messages...',
        hintStyle: TextStyle(color: Colors.white70),
        border: InputBorder.none,
      ),
      onSubmitted: (_) => _executeSearch(),
    );
  }

  List<Widget> _buildSearchActions() {
    return [
      if (_isSearchLoading)
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(color: Colors.white),
          ),
        )
      else ...[
        if (_searchResults.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              '${_currentSearchIndex + 1}/${_searchResults.length}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_up),
          tooltip: 'Previous Match',
          onPressed:
              _searchResults.length > 1
                  ? () => _navigateToSearchResult(-1)
                  : null,
        ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          tooltip: 'Next Match',
          onPressed:
              _searchResults.length > 1
                  ? () => _navigateToSearchResult(1)
                  : null,
        ),
      ],
    ];
  }

  Widget _buildSystemMessage(String content) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12.0),
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Text(
          content,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
            color: Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Widget _buildReactionsDisplay(Message message, bool isMe) {
    if (message.reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final Map<String, List<Reaction>> groupedReactions = {};
    for (var reaction in message.reactions) {
      groupedReactions.putIfAbsent(reaction.emoji, () => []).add(reaction);
    }

    return Positioned(
      bottom: -22,
      right: isMe ? 4 : null,
      left: !isMe ? 4 : null,
      child: GestureDetector(
        onTap: () {
          _showReactionsBottomSheet(context, message);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).canvasColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children:
                groupedReactions.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3.0),
                    child: IgnorePointer(
                      child: Text('${entry.key} ${entry.value.length}'),
                    ),
                  );
                }).toList(),
          ),
        ),
      ),
    );
  }

  void _showReactionsBottomSheet(BuildContext context, Message message) {
    final Map<String, List<Reaction>> groupedReactions = {};
    for (var reaction in message.reactions) {
      groupedReactions.putIfAbsent(reaction.emoji, () => []).add(reaction);
    }
    final emojis = groupedReactions.keys.toList();
    final allReactions = message.reactions;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (BuildContext context) {
        return DefaultTabController(
          length: emojis.length + 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                isScrollable: true,
                tabs: [
                  Tab(
                    child: Text(
                      'All ${allReactions.length}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  ...emojis.map(
                    (emoji) => Tab(
                      child: Text(
                        '$emoji ${groupedReactions[emoji]!.length}',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.3,
                child: TabBarView(
                  children: [
                    ListView.builder(
                      itemCount: allReactions.length,
                      itemBuilder: (context, index) {
                        final reaction = allReactions[index];
                        return ListTile(
                          leading: UserAvatar(
                            userName: reaction.userName,
                            radius: 18,
                          ),
                          title: Text(reaction.userName),
                          trailing: Text(
                            reaction.emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        );
                      },
                    ),
                    ...emojis.map((emoji) {
                      final reactors = groupedReactions[emoji]!;
                      return ListView.builder(
                        itemCount: reactors.length,
                        itemBuilder: (context, index) {
                          final reactor = reactors[index];
                          return ListTile(
                            leading: UserAvatar(
                              userName: reactor.userName,
                              radius: 18,
                            ),
                            title: Text(reactor.userName),
                          );
                        },
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReactionPicker(BuildContext context, Message message) {
    final List<String> commonEmojis = ['❤️', '😂', '👍', '😢', '😮', '🙏'];

    final currentUserId = authService.currentUser?.id;
    Reaction? currentUserReaction;
    try {
      currentUserReaction = message.reactions.firstWhere(
        (r) => r.userId == currentUserId,
      );
    } catch (e) {
      currentUserReaction = null;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bc) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(25.0),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children:
                commonEmojis.map((emoji) {
                  final bool isSelected = currentUserReaction?.emoji == emoji;

                  return InkWell(
                    onTap: () {
                      socketService.reactToMessage(
                        _currentConversation.id,
                        message.id,
                        emoji,
                      );
                      Navigator.of(context).pop();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? Theme.of(
                                  context,
                                ).primaryColor.withOpacity(0.15)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 30)),
                    ),
                  );
                }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    final bool hasText = _messageController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.5),
            width: 0.8,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0, left: 4.0),
              child: IconButton(
                icon:
                    _isUploadingFile
                        ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                        : Icon(
                          Icons.attach_file_rounded,
                          color: Colors.grey[600],
                        ),
                onPressed: _isUploadingFile ? null : _pickAndSendFile,
              ),
            ),
            Expanded(
              child:
                  _isRecording
                      ? Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 18,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.mic,
                              color: Colors.red.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "Recording...",
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                      : Container(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(25.0),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).dividerColor.withOpacity(0.7),
                          ),
                        ),
                        child: TextField(
                          controller: _messageController,
                          onChanged: _onTypingChanged,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18.0,
                              vertical: 12.0,
                            ),
                            hintStyle: TextStyle(color: Colors.grey[500]),
                          ),
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          keyboardType: TextInputType.multiline,
                        ),
                      ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onLongPress: hasText || _isRecording ? null : _startRecording,
              onLongPressUp: hasText || !_isRecording ? null : _stopRecording,
              child: Material(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(25),
                child: InkWell(
                  borderRadius: BorderRadius.circular(25),
                  onTap: hasText ? _sendMessage : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Icon(
                      hasText ? Icons.send_rounded : Icons.mic_none_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
