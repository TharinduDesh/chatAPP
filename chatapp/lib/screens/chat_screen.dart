// lib/screens/chat_screen.dart
import 'dart:async';
import 'dart:io'; // For File
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // For ImagePicker
import '../services/services_locator.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../widgets/user_avatar.dart';
import 'package:intl/intl.dart';
import 'home_screen.dart';
import 'add_members_to_group_screen.dart';
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
  String? _errorMessage;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _activeUsersSubscription;
  StreamSubscription? _conversationUpdateSubscription;
  StreamSubscription? _messageStatusUpdateSubscription;

  User? _currentUser;
  late Conversation _currentConversation;

  bool _isOtherUserTyping = false;
  bool _isTargetUserOnline = false;
  Timer? _typingTimer;
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
    );
    _messageController.clear();
    if (!isGroupChat) _emitStopTyping();
    _scrollToBottom();
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

  Widget _buildMessageItem(Message message, bool isConsecutive) {
    final bool isMe = message.sender.id == _currentUser?.id;
    final Radius cornerRadius = const Radius.circular(18.0);
    final Radius tailRadius = const Radius.circular(4.0);

    return Container(
      // Reduce top margin for consecutive messages
      margin: EdgeInsets.only(
        top: isConsecutive ? 4.0 : 12.0,
        left: 16.0,
        right: 16.0,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            // Show avatar only for the last message in a consecutive block from others
            Opacity(
              opacity: !isConsecutive ? 1.0 : 0.0,
              child: UserAvatar(
                imageUrl: message.sender.profilePictureUrl,
                userName: message.sender.fullName,
                radius: 16,
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Show sender's name only for the first message in a block in group chats
                if (!isMe && isGroupChat && !isConsecutive)
                  Padding(
                    padding: const EdgeInsets.only(left: 12.0, bottom: 4.0),
                    child: Text(
                      message.sender.fullName.split(' ').first,
                      style: TextStyle(fontSize: 12.0, color: Colors.grey[600]),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14.0,
                    vertical: 10.0,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isMe
                            ? Theme.of(context).primaryColor
                            : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.only(
                      topLeft: cornerRadius,
                      topRight: cornerRadius,
                      // "Tail" points towards sender
                      bottomLeft: isMe ? cornerRadius : tailRadius,
                      bottomRight: isMe ? tailRadius : cornerRadius,
                    ),
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 15.5,
                      height: 1.35,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    top: 4.0,
                    left: 8.0,
                    right: 8.0,
                  ),
                  child: Text(
                    _formatMessageTimestamp(message.createdAt),
                    style: TextStyle(fontSize: 11.0, color: Colors.grey[500]),
                  ),
                ),
                if (isMe) ...[
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
                            ? Colors
                                .blueAccent // Blue ticks for 'read'
                            : Colors.grey[500],
                  ),
                ],
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null)
      return Scaffold(
        body: Center(
          child: Text(
            "User not authenticated.",
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
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
                    ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text(
                          isGroupChat
                              ? 'No messages in this group yet.\nBe the first to say something!'
                              : 'No messages yet.\nStart the conversation with ${widget.otherUser.fullName.split(' ').first}!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                            height: 1.5,
                          ),
                        ),
                      ),
                    )
                    // <<< MODIFIED: Replaced ListView.builder with AnimatedList >>>
                    : AnimatedList(
                      key: _listKey,
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      initialItemCount: _messages.length,
                      itemBuilder: (context, index, animation) {
                        final bool showDateSeparator = _shouldShowDateSeparator(
                          index,
                        );
                        final bool isConsecutive = _isConsecutiveMessage(index);
                        final message = _messages[index];

                        Widget messageWidget = _buildMessageItem(
                          message,
                          isConsecutive,
                        );
                        if (showDateSeparator) {
                          messageWidget = Column(
                            children: [
                              _DateSeparator(message.createdAt.toLocal()),
                              messageWidget,
                            ],
                          );
                        }

                        // Wrap the message item with a slide/fade transition
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.5),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOut,
                              ),
                            ),
                            child: messageWidget,
                          ),
                        );
                      },
                    ),
          ),
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
