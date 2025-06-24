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
  List<Message> _messages = [];
  bool _isLoadingMessages = true;
  bool _isUploadingFile = false;
  String? _errorMessage;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _activeUsersSubscription;
  StreamSubscription? _conversationUpdateSubscription;
  StreamSubscription? _messageStatusUpdateSubscription;

  Message? _replyingToMessage;

  User? _currentUser;
  late Conversation _currentConversation;

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

    if (_currentUser == null) {
      _handleInvalidSession();
      return;
    }

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
        // <<< MODIFIED: Animate new message in >>>
        final int insertIndex = _messages.length;
        setState(() {
          _messages.add(newMessage);
          if (!isGroupChat &&
              widget.otherUser.id.isNotEmpty &&
              newMessage.sender.id == widget.otherUser.id) {
            _isOtherUserTyping = false;
          }
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
                  if (message.sender.id == _currentUser?.id &&
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
    if (message.sender.id != _currentUser?.id || message.deletedAt != null)
      return;

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
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _activeUsersSubscription?.cancel();
    _conversationUpdateSubscription?.cancel();
    _messageStatusUpdateSubscription?.cancel();
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
      (m) => m.sender.id == widget.otherUser.id && m.status != 'read',
    );

    if (hasUnreadMessages) {
      print("ChatScreen: Marking visible messages as read...");
      // Tell the server to mark all messages in this conversation as read by me.
      socketService.markMessagesAsRead(_currentConversation.id);

      // Also optimistically update the local state for immediate feedback, though
      // the server's broadcast (`messagesRead` event) would eventually do this too.
      setState(() {
        for (var message in _messages) {
          if (message.sender.id != _currentUser?.id) {
            // This local update is less critical if the sender's UI is what we care about.
            // The main purpose of the socket event is to update the *sender's* UI.
          }
        }
      });
    }
  }

  Future<void> _fetchMessages() async {
    if (!mounted) return;
    setState(() {
      _isLoadingMessages = true;
      _errorMessage = null;
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
        _scrollToBottom(KindaSoon: true);
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

  void _sendMessage() {
    final String text = _messageController.text.trim();
    if (text.isEmpty || _currentUser == null) return;
    socketService.sendMessage(
      conversationId: _currentConversation.id,
      senderId: _currentUser!.id,
      content: text,
      replyTo: _replyingToMessage?.id,
      replySnippet: _replyingToMessage?.content,
      replySenderName: _replyingToMessage?.sender.fullName,
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
          replySenderName: _replyingToMessage?.sender.fullName,
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

  void _scrollToBottom({bool KindaSoon = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (KindaSoon) {
          Future.delayed(const Duration(milliseconds: 150), () {
            if (_scrollController.hasClients)
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
          });
        } else {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
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
    return previousMessage.sender.id == currentMessage.sender.id &&
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
        messageToReplyTo.sender.id == _currentUser?.id;

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
                  isReplyingToSelf ? 'You' : messageToReplyTo.sender.fullName,
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
    final bool isMe = message.sender.id == _currentUser?.id;
    final bool isDeleted = message.deletedAt != null;

    // First, determine the core content of the bubble.
    // The helper methods (_buildTextBubble, _buildFileBubble) are now responsible
    // for also including the reply preview inside them.
    Widget messageContent;
    if (isDeleted) {
      // If deleted, it's always a simple text bubble with placeholder content.
      messageContent = _buildTextBubble(
        message,
        isMe,
        BorderRadius.circular(18.0),
      );
    } else if (message.fileUrl != null && message.fileUrl!.isNotEmpty) {
      // If it has a file, build the file bubble.
      messageContent = _buildFileBubble(
        message,
        isMe,
        BorderRadius.circular(18.0),
      );
    } else {
      // Otherwise, it's a standard text bubble.
      messageContent = _buildTextBubble(
        message,
        isMe,
        BorderRadius.circular(18.0),
      );
    }

    // Now, we build the full message layout, including avatar, gestures, and metadata.
    return Container(
      margin: EdgeInsets.only(
        top: isConsecutive ? 4.0 : 12.0,
        bottom: 4.0,
        left: 16.0,
        right: 16.0,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Show avatar for the other user on non-consecutive messages.
          if (!isMe && !isConsecutive)
            UserAvatar(
              imageUrl: message.sender.profilePictureUrl,
              userName: message.sender.fullName,
              radius: 16,
            )
          else if (!isMe)
            const SizedBox(
              width: 32,
            ), // Keep alignment for consecutive messages.

          const SizedBox(width: 8),

          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Show sender's name in group chats for non-consecutive messages.
                if (!isMe && isGroupChat && !isConsecutive)
                  Padding(
                    padding: const EdgeInsets.only(left: 12.0, bottom: 4.0),
                    child: Text(
                      message.sender.fullName.split(' ').first,
                      style: TextStyle(fontSize: 12.0, color: Colors.grey[600]),
                    ),
                  ),

                // The main message bubble, now wrapped in all necessary gestures.
                // The reply preview is now handled *inside* the messageContent widget.
                Dismissible(
                  key: Key(message.id),
                  direction: DismissDirection.startToEnd,
                  confirmDismiss: (direction) async {
                    if (!isDeleted) {
                      setState(() {
                        _replyingToMessage = message;
                      });
                    }
                    return false; // Prevent dismissal.
                  },
                  background: Align(
                    alignment:
                        isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Icon(
                        Icons.reply,
                        color: isMe ? Colors.white : Colors.black54,
                      ),
                    ),
                  ),
                  child: GestureDetector(
                    onLongPress: () => _showMessageOptions(context, message),
                    child: messageContent,
                  ),
                ),

                // Timestamp and read receipt status.
                Padding(
                  padding: const EdgeInsets.only(
                    top: 4.0,
                    left: 12.0,
                    right: 12.0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatMessageTimestamp(message.createdAt),
                        style: TextStyle(
                          fontSize: 11.0,
                          color: Colors.grey[500],
                        ),
                      ),
                      if (isMe && !isDeleted) ...[
                        const SizedBox(width: 5),
                        Icon(
                          message.status == 'read'
                              ? Icons.done_all_rounded
                              : message.status == 'delivered'
                              ? Icons.done_all_rounded
                              : Icons.done_rounded,
                          size: 16.0,
                          color:
                              message.status == 'read'
                                  ? Colors.blueAccent
                                  : Colors.grey[500],
                        ),
                      ],
                    ],
                  ),
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
        // TODO: In a future step, you can implement scroll-to-message functionality here.
        // For now, it's just a visual element.
        print("Tapped reply context for message ID: ${message.replyTo}");
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color:
            isMe
                ? (isDeleted
                    ? Colors.grey[800]
                    : Theme.of(context).primaryColor)
                : (isDeleted ? Colors.grey[300] : Theme.of(context).cardColor),
        borderRadius: borderRadius,
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
          if (message.isEdited && !isDeleted)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                "(edited)",
                style: TextStyle(
                  fontSize: 12,
                  color: isMe ? Colors.white70 : Colors.black54,
                ),
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

    // Decide what UI to show inside the bubble
    Widget fileContent;
    if (isImage) {
      fileContent = _buildImageContent(message, isMe);
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
        leadingWidth: 30,
        titleSpacing: 0,
        title: GestureDetector(
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
                      const Text(
                        'Offline',
                        style: TextStyle(fontSize: 12, color: Colors.white54),
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
        ),
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
                    ? Center(/* ... your empty message placeholder ... */)
                    : AnimatedList(
                      key: _listKey,
                      controller: _scrollController,
                      reverse:
                          false, // Keep this to show latest messages at the bottom
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      initialItemCount: _messages.length,
                      // The itemBuilder's job is to build each list item.
                      // It should NOT call the parent _buildMessageItem method.
                      itemBuilder: (context, index, animation) {
                        final message = _messages[index];
                        final isConsecutive = _isConsecutiveMessage(index);
                        final showDateSeparator = _shouldShowDateSeparator(
                          index,
                        );

                        // The actual message bubble widget is built by our helper
                        final messageWidget = _buildMessageItem(
                          message,
                          isConsecutive,
                        );

                        // We combine the date separator and the message bubble here
                        return Column(
                          children: [
                            if (showDateSeparator)
                              _DateSeparator(message.createdAt.toLocal()),
                            FadeTransition(
                              opacity: animation,
                              child: messageWidget,
                            ),
                          ],
                        );
                      },
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

  Widget _buildMessageInput() {
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
            // <<< NEW: Attachment Button >>>
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0, left: 4.0),
              child: IconButton(
                icon:
                    _isUploadingFile
                        ? SizedBox(
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
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(25.0),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.7),
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
            Material(
              color: Theme.of(context).primaryColor,
              borderRadius: BorderRadius.circular(25),
              child: InkWell(
                borderRadius: BorderRadius.circular(25),
                onTap: _sendMessage,
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 24,
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
