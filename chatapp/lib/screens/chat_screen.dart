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
  // <<< NEW: Key for AnimatedList >>>
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};

  List<Message> _messages = [];
  bool _isLoadingMessages = true;
  bool _isUploadingFile = false;
  String? _errorMessage;
  // NEW: To track the message that should be temporarily highlighted
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

  // NEW: For audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _audioPath;

  // State variables for search
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<Message> _searchResults = [];
  int _currentSearchIndex = 0;
  bool _isSearchLoading = false;

  // State variables for pagination
  int _currentPage = 1;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;

  bool _isOtherUserTyping = false;
  bool _isTargetUserOnline = false;
  Timer? _typingTimer;
  String? _downloadingFileId;
  bool _isLeavingGroup = false;
  // Tracks loading state for remove/make admin/demote admin for a specific member
  // Key: Member ID, Value: true if an admin action is in progress for this member
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
    //Add the scroll listener for pagination
    _scrollController.addListener(_scrollListener);

    if (_currentUser == null) {
      _handleInvalidSession();
      return;
    }

    _messageController.addListener(() {
      if (mounted) {
        setState(() {
          // This empty setState call is enough to trigger a rebuild
        });
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

    // <<< NEW: Mark messages as read when entering the screen >>>
    // if (widget.conversation.unreadCount > 0) {
    //   _markConversationAsRead();
    // }

    _markConversationAsRead();

    _fetchMessages();
    socketService.joinConversation(_currentConversation.id);
    _subscribeToSocketEvents();
    _checkInitialOnlineStatus();

    // <<< NEW: Immediately mark messages as read when entering screen >>>
    // We do this after a small delay to ensure the view is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markVisibleMessagesAsRead();
    });
  }

  void _scrollListener() {
    // If we're at the top of the list and not already loading, fetch more
    if (_scrollController.position.pixels ==
            _scrollController.position.minScrollExtent &&
        !_isLoadingMore) {
      _fetchMoreMessages();
    }
  }

  // <<< NEW METHOD >>>
  void _markConversationAsRead() {
    print(
      "ChatScreen: Marking conversation ${widget.conversation.id} as read on server.",
    );
    // This is a "fire-and-forget" call. We don't need to wait for it.
    // The UI has already been updated optimistically in HomeScreen.
    chatService.markAsRead(widget.conversation.id).catchError((e) {
      // Don't show a disruptive error, just log it.
      print("ChatScreen: Background 'mark as read' failed: $e");
    });
  }

  void _handleInvalidSession() {
    print("ChatScreen Error: Current user is null! Navigating back.");
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
    _messageSubscription = socketService.messageStream.listen((newMessage) {
      if (newMessage.conversationId == _currentConversation.id && mounted) {
        // MODIFIED: Added a null check for newMessage.sender
        if (!isGroupChat &&
            widget.otherUser.id.isNotEmpty &&
            newMessage.sender?.id == widget.otherUser.id) {
          setState(() {
            _isOtherUserTyping = false;
          });
        }
        // <<< MODIFIED: Animate new message in >>>
        final int insertIndex = _messages.length;
        setState(() {
          _messages.add(newMessage);
        });
        _listKey.currentState?.insertItem(
          insertIndex,
          duration: const Duration(milliseconds: 400),
        );
        _scrollToBottom();
      }
    });

    // <<< NEW: Listen for status updates from SocketService >>>
    _messageStatusUpdateSubscription = socketService.messageStatusUpdateStream
        .listen((update) {
          if (update['conversationId'] == _currentConversation.id && mounted) {
            setState(() {
              if (update['status'] == 'read') {
                // All messages from the other user have been read. Update all relevant messages.
                for (var message in _messages) {
                  if (message.sender?.id == _currentUser?.id &&
                      message.status != 'read') {
                    message.status = 'read';
                  }
                }
              } else if (update['status'] == 'delivered') {
                // A specific message has been delivered.
                final messageId = update['messageId'];
                final messageIndex = _messages.indexWhere(
                  (m) => m.id == messageId,
                );
                if (messageIndex != -1 &&
                    _messages[messageIndex].status == 'sent') {
                  _messages[messageIndex].status = 'delivered';
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
      _activeUsersSubscription = socketService.activeUsersStream.listen((
        activeIds,
      ) {
        if (mounted)
          setState(() {
            _isTargetUserOnline = activeIds.contains(widget.otherUser.id);
          });
      });
    }
  }

  void _checkInitialOnlineStatus() {
    if (!isGroupChat && widget.otherUser.id.isNotEmpty) {
      // Initial check for online status can be done here if SocketService provides a method.
      // For now, relying on the stream to update.
    }
  }

  // Method to show options
  void _showMessageOptions(BuildContext context, Message message) {
    // Only show options for the current user's own messages that are not deleted
    if (message.sender == null ||
        message.sender!.id != _currentUser?.id ||
        message.deletedAt != null) {
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showEditDialog(message);
                },
              ),
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

  // Method to show the edit dialog
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
                    // Find and update the message in the local list
                    setState(() {
                      final index = _messages.indexWhere(
                        (m) => m.id == updatedMessage.id,
                      );
                      if (index != -1) {
                        _messages[index] = updatedMessage;
                      }
                    });
                  } catch (e) {
                    /* handle error */
                  }
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
    );
  }

  // Method to confirm deletion
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
                    /* handle error */
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
    if (socketService.socket != null && socketService.socket!.connected)
      socketService.leaveConversation(_currentConversation.id);
    super.dispose();
  }

  // <<< NEW: Method to tell the server what has been read >>>
  void _markVisibleMessagesAsRead() {
    if (isGroupChat) return; // Logic is for 1-to-1 for now

    // Find any messages from the other user that are not yet marked as 'read'.
    final bool hasUnreadMessages = _messages.any(
      (m) => m.sender?.id == widget.otherUser.id && m.status != 'read',
    );

    if (hasUnreadMessages) {
      print("ChatScreen: Marking visible messages as read...");
      // Tell the server to mark all messages in this conversation as read by me.
      socketService.markMessagesAsRead(_currentConversation.id);

      // Also optimistically update the local state for immediate feedback, though
      // the server's broadcast (`messagesRead` event) would eventually do this too.
      // setState(() {
      //   for (var message in _messages) {
      //     if (message.sender.id != _currentUser?.id) {
      //       // This local update is less critical if the sender's UI is what we care about.
      //       // The main purpose of the socket event is to update the *sender's* UI.
      //     }
      //   }
      // });
    }
  }

  Future<void> _fetchMessages() async {
    if (!mounted) return;
    setState(() {
      _isLoadingMessages = true;
      _errorMessage = null;
      _currentPage = 1; // Reset to page 1
      _hasMoreMessages = true; // Reset
    });
    try {
      final messages = await chatService.getMessages(_currentConversation.id);
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoadingMessages = false;
        });
        // Now that we know exactly which messages arrived, tell the server to mark them read:
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

  Future<void> _fetchMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);

    _currentPage++; // Go to the next page

    try {
      final newMessages = await chatService.getMessages(
        _currentConversation.id,
        page: _currentPage,
      );

      if (newMessages.isEmpty) {
        // If we get an empty list, there are no more messages to load
        setState(() => _hasMoreMessages = false);
      } else {
        // Insert the new (older) messages at the beginning of our list
        _messages.insertAll(0, newMessages);
      }
    } catch (e) {
      print("Failed to load more messages: $e");
      // Optionally show a snackbar or revert the page counter
      _currentPage--;
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _sendMessage() {
    final String text = _messageController.text.trim();
    if (text.isEmpty || _currentUser == null) return;
    socketService.sendMessage(
      conversationId: _currentConversation.id,
      senderId: _currentUser!.id,
      content: text,
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

        // <<< MODIFIED: Navigate to Preview Screen >>>
        // We push the new screen and wait for it to pop. It will return the caption.
        final String? caption = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (context) => FilePreviewScreen(file: file),
          ),
        );

        // If the user closed the preview screen without sending, caption will be null.
        if (caption == null) return;

        // If the user pressed send, proceed with uploading and sending the message
        setState(() => _isUploadingFile = true);

        // 1. Upload the file
        final fileData = await chatService.uploadChatFile(file);

        // 2. Send the message via socket with the file URL and caption
        socketService.sendMessage(
          conversationId: _currentConversation.id,
          senderId: _currentUser!.id,
          content: caption, // Use the caption from the preview screen
          fileUrl: fileData['fileUrl'],
          fileType: fileData['fileType'],
          fileName: fileData['fileName'],
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
        // Get a writable directory path
        final tempDir = await getTemporaryDirectory();
        // Create a full, valid path for the audio file
        final filePath = p.join(
          tempDir.path,
          'voice_message_${DateTime.now().millisecondsSinceEpoch}.m4a',
        );

        print("DEBUG: Recording will be saved to: $filePath");

        // Start recording to the valid path
        await _audioRecorder.start(const RecordConfig(), path: filePath);

        setState(() {
          _isRecording = true;
        });
      } else {
        print("DEBUG: Microphone permission was denied.");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Microphone permission not granted.")),
        );
      }
    } catch (e) {
      print("DEBUG: Error starting recording: $e");
    }
  }

  // NEW: Add a method to start or stop searching
  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      // Reset search state when closing
      if (!_isSearching) {
        _searchController.clear();
        _searchResults = [];
        _currentSearchIndex = 0;
        _highlightedMessageId = null;
      }
    });
  }

  // NEW: Method to execute the search
  // Method to execute the search
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
      ).showSnackBar(SnackBar(content: Text("Search failed: ${e.toString()}")));
    } finally {
      if (mounted) {
        setState(() => _isSearchLoading = false);
      }
    }
  }

  // NEW: Method to navigate search results
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

  // NEW: Method to stop recording and send the file
  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (path == null) return;

      setState(() {
        _isRecording = false;
        _audioPath = path;
      });

      // Send the recorded file
      File file = File(path);
      setState(() => _isUploadingFile = true);

      final fileData = await chatService.uploadChatFile(file);

      socketService.sendMessage(
        conversationId: _currentConversation.id,
        senderId: _currentUser!.id,
        content: '', // No text content for voice message
        fileUrl: fileData['fileUrl'],
        fileType: fileData['fileType'],
        fileName: fileData['fileName'],
      );
    } catch (e) {
      print("Error stopping recording: $e");
    } finally {
      if (mounted) setState(() => _isUploadingFile = false);
    }
  }

  void _scrollToBottom() {
    // Use addPostFrameCallback to make sure the new item is built
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

      setDialogState(() {
        /* Show loading for picture change if needed */
      });

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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update group picture: ${e.toString().replaceFirst("Exception: ", "")}',
            ),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted)
        setDialogState(() {
          /* Reset loading state */
        });
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
                              // setDialogSaveState(() => isSavingName = false); // Dialog is popped, no need to set state
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

  // Last Seen

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

  /// Scrolls the list to the message with the given ID.
  void _scrollToRepliedMessage(String? repliedMessageId) {
    if (repliedMessageId == null) return;

    final targetKey = _messageKeys[repliedMessageId];
    final targetContext = targetKey?.currentContext;

    if (targetContext != null) {
      // The message is visible on screen, scroll to it
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.5, // Aligns the message to the center of the viewport
      );
      // Trigger the highlight effect
      _highlightRepliedMessage(repliedMessageId);
    } else {
      // If the message is not in the current view (e.g., it's much older)
      // For now, we just show a snackbar. A more advanced implementation
      // could fetch older messages until the target is found.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Original message not currently loaded."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Temporarily highlights a message to draw the user's attention.
  void _highlightRepliedMessage(String messageId) {
    setState(() {
      _highlightedMessageId = messageId;
    });

    // Remove the highlight after 2 seconds
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
      if (mounted)
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

  void _showGroupMembers(BuildContext context) {
    if (!_currentConversation.isGroupChat) return;
    _editGroupNameController.text = _currentConversation.groupName ?? "";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            // Re-check admin status based on potentially updated _currentConversation
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
                        padding: const EdgeInsets.fromLTRB(
                          16.0,
                          0,
                          16.0,
                          8.0,
                        ), // Adjusted padding
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
                              // Don't pop dialogContext here, let AddMembers return new convo
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
                                }); // Update main screen
                                setDialogState(() {}); // Refresh this dialog
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
                                            if (action == 'remove')
                                              _confirmRemoveMember(
                                                dialogContext,
                                                member,
                                                setDialogState,
                                              );
                                            else if (action == 'make_admin')
                                              _confirmPromoteToAdmin(
                                                dialogContext,
                                                member,
                                                setDialogState,
                                              );
                                            else if (action == 'demote_admin')
                                              _confirmDemoteAdmin(
                                                dialogContext,
                                                member,
                                                setDialogState,
                                              );
                                          },
                                          itemBuilder:
                                              (
                                                BuildContext context,
                                              ) => <PopupMenuEntry<String>>[
                                                if (!isMemberAdmin) // Can promote if not already admin
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
                                                        1) // Can demote if they are admin AND not the only admin
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
                                    : null, // No actions for self or if current user is not an admin
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
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to remove member: ${e.toString().replaceFirst("Exception: ", "")}',
              ),
              backgroundColor: Colors.red,
            ),
          );
      } finally {
        if (mounted)
          setDialogStateInParent(() {
            _isManagingMemberMap.remove(memberToRemove.id);
          });
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
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to promote to admin: ${e.toString().replaceFirst("Exception: ", "")}',
              ),
              backgroundColor: Colors.red,
            ),
          );
      } finally {
        if (mounted)
          setDialogStateInParent(() {
            _isManagingMemberMap.remove(memberToPromote.id);
          });
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
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to demote admin: ${e.toString().replaceFirst("Exception: ", "")}',
              ),
              backgroundColor: Colors.red,
            ),
          );
      } finally {
        if (mounted)
          setDialogStateInParent(() {
            _isManagingMemberMap.remove(adminToDemote.id);
          });
      }
    }
  }

  void _showOtherUserDetails(BuildContext context) {
    /* ... existing code ... */
    if (_currentConversation.isGroupChat || widget.otherUser.id.isEmpty) return;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
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
                    isActive: _isTargetUserOnline,
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
                          _isTargetUserOnline
                              ? Colors.greenAccent[700]
                              : Colors.grey[400],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isTargetUserOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            _isTargetUserOnline
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
  }

  Future<void> _confirmLeaveGroup() async {
    /* ... existing code ... */
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
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to leave group: ${e.toString().replaceFirst("Exception: ", "")}',
              ),
              backgroundColor: Colors.red,
            ),
          );
      } finally {
        if (mounted)
          setState(() {
            _isLeavingGroup = false;
          });
      }
    }
  }

  // <<< NEW HELPER METHOD for date checking >>>
  bool _shouldShowDateSeparator(int currentIndex) {
    if (currentIndex == 0) {
      return true; // Always show date for the first message
    }
    final previousMessage = _messages[currentIndex - 1];
    final currentMessage = _messages[currentIndex];
    // Check if the day is different
    final previousDate = DateUtils.dateOnly(
      previousMessage.createdAt.toLocal(),
    );
    final currentDate = DateUtils.dateOnly(currentMessage.createdAt.toLocal());
    return !DateUtils.isSameDay(previousDate, currentDate);
  }

  // <<< NEW HELPER for checking consecutive messages >>>
  bool _isConsecutiveMessage(int currentIndex) {
    if (currentIndex == 0) return false; // First message is never consecutive
    final previousMessage = _messages[currentIndex - 1];
    final currentMessage = _messages[currentIndex];

    // Check if sender is the same and time difference is small (e.g., under a minute)
    if (previousMessage.sender == null || currentMessage.sender == null) {
      return false; // System messages are never consecutive.
    }

    // This part now only runs if both messages have a sender.
    return previousMessage.sender!.id == currentMessage.sender!.id &&
        currentMessage.createdAt
                .difference(previousMessage.createdAt)
                .inMinutes <
            1;
  }

  // In lib/screens/chat_screen.dart -> inside _ChatScreenState

  // This method builds the preview widget that appears above the text input field
  Widget _buildReplyPreview() {
    // This will never be null when the widget is built, so we can use `!`
    final messageToReplyTo = _replyingToMessage!;
    final bool isReplyingToSelf =
        messageToReplyTo.sender?.id == _currentUser?.id;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 4), // Margin for spacing
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.08),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
        // A colored left border to indicate a reply
        border: Border(
          left: BorderSide(color: Theme.of(context).primaryColor, width: 4),
        ),
      ),
      child: Row(
        children: [
          // The main content of the preview
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Show "You" if replying to your own message
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
                  // If it's a file message, show the file name. Otherwise, show text content.
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
          // A close button to cancel the reply action
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              setState(() {
                // Clear the reply state when the user taps close
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

    // This part that defines messageContent remains the same
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

    return AnimatedContainer(
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
        bottom:
            message.reactions.isNotEmpty
                ? 16.0
                : 4.0, // Add bottom margin if there are reactions
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
                    // The message bubble itself, with gestures for replying and reacting
                    GestureDetector(
                      onLongPress: () {
                        if (!isDeleted) _showReactionPicker(context, message);
                      },
                      onDoubleTap: () {
                        if (!isDeleted) _showMessageOptions(context, message);
                      },
                      child: messageContent,
                    ),

                    // The reactions display, positioned relative to the bubble
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
  }

  // In lib/screens/chat_screen.dart -> inside _ChatScreenState

  Widget _buildReplyPreviewWidget(Message message, bool isMe) {
    return GestureDetector(
      onTap: () {
        _scrollToRepliedMessage(message.replyTo);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          // Use a slightly different color to distinguish the reply context from the main bubble
          color:
              isMe
                  ? Colors.white.withOpacity(0.2)
                  : Colors.black.withOpacity(0.05),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          // The colored left border is a common UI pattern for replies
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
              // Display the name of the person who sent the original message
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
              // Display a snippet of the original message content or its file name
              (message.replySnippet != null && message.replySnippet!.isNotEmpty)
                  ? message.replySnippet!
                  : "📄 File", // Fallback for file replies with no text
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
        // Use a Stack to layer content and timestamp
        children: [
          // This Padding ensures the main text doesn't overlap with the timestamp
          Padding(
            padding: EdgeInsets.only(
              right: 70, // Reserve space for time and icon
              bottom:
                  message.isEdited
                      ? 15.0
                      : 0.0, // Reserve space for "(edited)" text
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
          // This Positioned widget holds the timestamp and read receipt
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
                  Icon(
                    message.status == 'read'
                        ? Icons.done_all_rounded
                        : Icons.done_all_rounded,
                    size: 16.0,
                    color:
                        message.status == 'read'
                            ? Colors.lightBlueAccent
                            : Colors.white70,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // In lib/screens/chat_screen.dart -> inside _ChatScreenState

  // 1. This is the main method you'll call from your list builder.
  // It decides which kind of bubble to build and handles the tap.
  Widget _buildFileBubble(
    Message message,
    bool isMe,
    BorderRadius borderRadius,
  ) {
    final fileType = message.fileType ?? '';
    final isImage = fileType.startsWith('image/');
    final isPdf = fileType == 'application/pdf';
    final isAudio = fileType.startsWith('audio/');

    // Decide what UI to show inside the bubble
    Widget fileContent;
    if (isImage) {
      fileContent = _buildImageContent(message, isMe);
    } else if (isAudio) {
      // Handle audio files
      final fullAudioUrl = '$SERVER_ROOT_URL${message.fileUrl!}';
      fileContent = VoiceMessageBubble(audioUrl: fullAudioUrl, isMe: isMe);
    } else {
      fileContent = _buildGenericFileContent(message, isMe, isPdf);
    }

    // Return the final bubble, wrapped in a container and a gesture detector
    return Container(
      width: MediaQuery.of(context).size.width * 0.65,
      decoration: BoxDecoration(
        color:
            isMe
                ? Theme.of(context).primaryColor.withAlpha(220)
                : Theme.of(context).cardColor,
        borderRadius: borderRadius,
      ),
      // Use a ClipRRect to ensure the ripple effect from GestureDetector respects the bubble's border radius
      child: ClipRRect(
        borderRadius: borderRadius,
        child: GestureDetector(
          onTap: () {
            final fullFileUrl = '$SERVER_ROOT_URL${message.fileUrl!}';

            if (isImage) {
              // Image viewing remains the same
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
              // <<< MODIFIED: Navigate to the new Syncfusion viewer screen >>>
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
              // For other files, you can still use url_launcher if you want
              // Or just show a message
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
              // Conditionally add the reply preview widget if this is a reply
              if (message.replyTo != null)
                Padding(
                  // Add some padding to space it nicely inside the bubble
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: _buildReplyPreviewWidget(message, isMe),
                ),

              // The file content (image or generic file) goes here
              fileContent,
            ],
          ),
        ),
      ),
    );
  }

  // 2. A helper method specifically for building the image bubble's content
  Widget _buildImageContent(Message message, bool isMe) {
    final fullImageUrl = '$SERVER_ROOT_URL${message.fileUrl!}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The Hero widget allows for the smooth animation to the full-screen view
        Hero(
          tag: message.id, // Must be a unique tag
          child: ClipRRect(
            // This ensures the image corners are rounded only at the top
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(18.0),
            ),
            child: Image.network(
              fullImageUrl,
              height: 200,
              fit: BoxFit.cover,
              // Show a loading indicator while the image downloads
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
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
              // Show an error icon if the image fails to load
              errorBuilder:
                  (context, error, stack) => Container(
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
        // Display the caption below the image if it exists
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

  // 3. A helper method for building PDF and other file type bubbles
  Widget _buildGenericFileContent(Message message, bool isMe, bool isPdf) {
    // Check if the current message's ID matches the one being downloaded
    final bool isDownloading = _downloadingFileId == message.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // If this specific file is downloading, show a progress indicator.
              // Otherwise, show the appropriate file icon.
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
        // Display the caption below the file info if it exists
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
    return DateFormat.jm().format(
      dateTime.toLocal(),
    ); // Only show time, e.g., 10:30 AM
  }

  String _formatDateTime(DateTime dateTime) {
    /* ... existing code ... */
    final now = DateTime.now();
    final localDateTime = dateTime.toLocal();
    if (now.year == localDateTime.year &&
        now.month == localDateTime.month &&
        now.day == localDateTime.day)
      return DateFormat.jm().format(localDateTime);
    if (now.year == localDateTime.year &&
        now.month == localDateTime.month &&
        now.day - localDateTime.day == 1)
      return 'Yesterday ${DateFormat.jm().format(localDateTime)}';
    return DateFormat('MMM d, hh:mm a').format(localDateTime);
  }

  // <<< NEW WIDGET for the date separator >>>
  Widget _DateSeparator(DateTime date) {
    String formattedDate;
    final now = DateUtils.dateOnly(DateTime.now());
    final yesterday = DateUtils.addDaysToDate(now, -1);

    if (DateUtils.isSameDay(date, now)) {
      formattedDate = 'Today';
    } else if (DateUtils.isSameDay(date, yesterday)) {
      formattedDate = 'Yesterday';
    } else if (now.year == date.year) {
      formattedDate = DateFormat('MMMM d').format(date); // e.g., June 12
    } else {
      formattedDate = DateFormat('yMMMMd').format(date); // e.g., June 12, 2024
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

  // In lib/screens/chat_screen.dart

  @override
  Widget build(BuildContext context) {
    // This initial check is good.
    if (_currentUser == null) {
      return Scaffold(
        body: Center(
          child: Text(
            "User not authenticated.",
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    // This is the main screen layout
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        // Use a conditional leading widget
        leading:
            _isSearching
                ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close Search',
                  onPressed: _toggleSearch,
                )
                : null, // Let Flutter handle the default back button
        leadingWidth: _isSearching ? 56 : 30, // Adjust width for close icon
        titleSpacing: 0,
        // Conditionally show the search field or the default title
        title: _isSearching ? _buildSearchField() : _buildDefaultAppBarTitle(),
        // Conditionally show search actions or default actions
        actions: _isSearching ? _buildSearchActions() : _buildDefaultActions(),
      ),
      body: Column(
        children: [
          // 1. THE MESSAGE LIST
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
                    : Column(
                      children: [
                        // Show loading indicator at the top when fetching more messages
                        if (_isLoadingMore)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        Expanded(
                          child: AnimatedList(
                            key: _listKey,
                            controller: _scrollController,
                            reverse: false,
                            padding: const EdgeInsets.symmetric(vertical: 10.0),
                            // Use a special item count to account for the potential loading indicator
                            initialItemCount: _messages.length,
                            itemBuilder: (context, index, animation) {
                              // The rest of your itemBuilder logic remains exactly the same
                              final message = _messages[index];
                              final key = _messageKeys.putIfAbsent(
                                message.id,
                                () => GlobalKey(),
                              );

                              if (message.messageType == 'system') {
                                return _buildSystemMessage(message.content);
                              }

                              final isConsecutive = _isConsecutiveMessage(
                                index,
                              );
                              final showDateSeparator =
                                  _shouldShowDateSeparator(index);
                              final messageWidget = _buildMessageItem(
                                message,
                                isConsecutive,
                              );

                              return KeyedSubtree(
                                key: key,
                                child: Column(
                                  children: [
                                    if (showDateSeparator)
                                      _DateSeparator(
                                        message.createdAt.toLocal(),
                                      ),
                                    FadeTransition(
                                      opacity: animation,
                                      child: messageWidget,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
          ),

          // 2. THE REPLY PREVIEW WIDGET (Conditional)
          // This is the correct location. It will only show up when you swipe to reply.
          if (_replyingToMessage != null) _buildReplyPreview(),

          // 3. THE MESSAGE INPUT WIDGET
          _buildMessageInput(),
        ],
      ),
    );
  }

  // Create these helper methods to build parts of the AppBar

  // Builds the default title when not searching
  Widget _buildDefaultAppBarTitle() {
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
            isActive: isGroupChat ? false : _isTargetUserOnline,
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
                else if (!isGroupChat && _isTargetUserOnline)
                  const Text(
                    'Online',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  )
                else if (!isGroupChat)
                  Text(
                    // Use the formatter here
                    _formatLastSeen(widget.otherUser.lastSeen),
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  )
                else if (isGroupChat)
                  Text(
                    '${_currentConversation.participants.length} members',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Builds the default actions when not searching
  List<Widget> _buildDefaultActions() {
    return [
      IconButton(
        icon: const Icon(Icons.search),
        tooltip: 'Search Messages',
        onPressed: _toggleSearch,
      ),
      // You can add other actions like a video call button here if needed
    ];
  }

  // Builds the text input field for the search bar
  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      style: const TextStyle(color: Color.fromARGB(255, 0, 0, 0), fontSize: 17),
      cursorColor: const Color.fromARGB(255, 0, 0, 0),
      decoration: const InputDecoration(
        hintText: 'Search messages...',
        hintStyle: TextStyle(color: Colors.white70),
        border: InputBorder.none,
      ),
      onSubmitted: (_) => _executeSearch(),
    );
  }

  // Builds the up/down navigation actions for search results
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

  // Add inside _ChatScreenState

  // Widget to display the reactions at the bottom of a message
  // In _ChatScreenState

  Widget _buildReactionsDisplay(Message message, bool isMe) {
    if (message.reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final Map<String, List<Reaction>> groupedReactions = {};
    for (var reaction in message.reactions) {
      groupedReactions.putIfAbsent(reaction.emoji, () => []).add(reaction);
    }

    // GestureDetector now wraps the Positioned widget
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
    final allReactions = message.reactions; // Get a list of all reactions

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (BuildContext context) {
        // Use DefaultTabController to manage the tabs
        return DefaultTabController(
          // Length is now number of emojis + 1 for the "All" tab
          length: emojis.length + 1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // TabBar to show the different emoji reactions
              TabBar(
                isScrollable: true, // Allows tabs to scroll if there are many
                tabs: [
                  // 1. The new "All" tab is added here
                  Tab(
                    child: Text(
                      'All ${allReactions.length}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),

                  // 2. The rest of the emoji tabs are generated as before
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
              // TabBarView to show the list of users for each emoji
              SizedBox(
                // Constrain the height of the content
                height: MediaQuery.of(context).size.height * 0.3,
                child: TabBarView(
                  children: [
                    // 1. The ListView for the "All" tab
                    ListView.builder(
                      itemCount: allReactions.length,
                      itemBuilder: (context, index) {
                        final reaction = allReactions[index];
                        return ListTile(
                          leading: UserAvatar(
                            userName: reaction.userName,
                            // In a future step, you could fetch user avatars here
                            radius: 18,
                          ),
                          title: Text(reaction.userName),
                          // Show the emoji they reacted with
                          trailing: Text(
                            reaction.emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        );
                      },
                    ),

                    // 2. The rest of the emoji-specific views
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

  // Shows the emoji picker when a user long-presses a message
  void _showReactionPicker(BuildContext context, Message message) {
    final List<String> commonEmojis = ['❤️', '😂', '👍', '😢', '😮', '🙏'];

    // 1. Find the current user's existing reaction, if any.
    final currentUserId = authService.currentUser?.id;
    Reaction? currentUserReaction;
    try {
      currentUserReaction = message.reactions.firstWhere(
        (r) => r.userId == currentUserId,
      );
    } catch (e) {
      // This is normal, it just means the user hasn't reacted yet.
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
                  // 2. Check if the current emoji is the one selected by the user.
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
                    // 3. Apply a highlight based on the `isSelected` flag.
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
    // Check if the text field has any text to determine which icon to show
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
            // Attachment Button (remains the same)
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

            // Expanded section for Text Field or Recording Indicator
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

            // Send / Microphone Button
            GestureDetector(
              // Use onLongPress for recording voice notes
              onLongPress: hasText || _isRecording ? null : _startRecording,
              onLongPressUp: hasText || !_isRecording ? null : _stopRecording,
              child: Material(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(25),
                child: InkWell(
                  borderRadius: BorderRadius.circular(25),
                  // Regular tap only works for sending text
                  onTap: hasText ? _sendMessage : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Icon(
                      // Switch icon based on whether there is text
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
