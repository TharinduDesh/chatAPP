// lib/screens/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../services/services_locator.dart';
import '../models/conversation_model.dart';
import '../models/user_model.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'user_list_screen.dart';
import 'chat_screen.dart';
import '../widgets/user_avatar.dart';
import 'package:intl/intl.dart';
import 'select_group_members_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  static const String routeName = '/home';
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Conversation> _conversations = [];
  bool _isLoadingConversations = true;
  String? _errorMessage;
  StreamSubscription? _conversationUpdateSubscription;
  StreamSubscription? _newMessageSubscription;
  StreamSubscription? _activeUsersSubscription;
  Set<String> _activeUserIds = {};

  @override
  void initState() {
    super.initState();
    _initializeScreen();

    _conversationUpdateSubscription = socketService.conversationUpdateStream
        .listen((updatedConv) {
          if (mounted) {
            final index = _conversations.indexWhere(
              (c) => c.id == updatedConv.id,
            );
            if (index != -1) {
              setState(() {
                updatedConv.unreadCount = _conversations[index].unreadCount;
                _conversations[index] = updatedConv;
                _conversations.sort(
                  (a, b) => b.updatedAt.compareTo(a.updatedAt),
                );
              });
            } else {
              setState(() {
                _conversations.insert(0, updatedConv);
                _conversations.sort(
                  (a, b) => b.updatedAt.compareTo(a.updatedAt),
                );
              });
            }
          }
        });

    // CORRECTED: Only one listener for new messages
    _newMessageSubscription = socketService.messageStream.listen((newMessage) {
      if (mounted) {
        final int conversationIndex = _conversations.indexWhere(
          (c) => c.id == newMessage.conversationId,
        );
        if (conversationIndex != -1) {
          setState(() {
            Conversation oldConv = _conversations[conversationIndex];
            _conversations[conversationIndex] = Conversation(
              id: oldConv.id,
              participants: oldConv.participants,
              isGroupChat: oldConv.isGroupChat,
              groupName: oldConv.groupName,
              groupAdmins:
                  oldConv.groupAdmins, // Using correct 'groupAdmins' property
              groupPictureUrl: oldConv.groupPictureUrl,
              lastMessage: newMessage,
              createdAt: oldConv.createdAt,
              updatedAt: newMessage.createdAt,
              // Increment unread count only if the message is from another user
              unreadCount:
                  (newMessage.sender.id != authService.currentUser?.id)
                      ? (oldConv.unreadCount) + 1
                      : oldConv.unreadCount,
            );
            // Bring the updated conversation to the top of the list
            _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          });
        } else {
          // If a message arrives for a conversation not in our list, refresh the whole list.
          _fetchConversations();
        }
      }
    });

    _activeUsersSubscription = socketService.activeUsersStream.listen((
      activeIds,
    ) {
      if (mounted) {
        setState(() {
          _activeUserIds = activeIds.toSet();
        });
      }
    });
  }

  Future<void> _initializeScreen() async {
    if (authService.currentUser != null) {
      if (socketService.socket == null || !socketService.socket!.connected) {
        await initializeServicesOnLogin();
      }
      _fetchConversations();
    } else {
      if (mounted) {
        setState(() {
          _isLoadingConversations = false;
          _errorMessage = "User not authenticated. Please login.";
        });
      }
    }
  }

  @override
  void dispose() {
    _conversationUpdateSubscription?.cancel();
    _newMessageSubscription?.cancel();
    _activeUsersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchConversations() async {
    if (authService.currentUser == null) {
      if (mounted)
        setState(() {
          _isLoadingConversations = false;
          _errorMessage = "Not logged in.";
        });
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoadingConversations = true;
      _errorMessage = null;
    });
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      final conversations = await chatService.getConversations();
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _isLoadingConversations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst("Exception: ", "");
          _isLoadingConversations = false;
        });
      }
    }
  }

  Future<void> _logoutUser() async {
    await authService.logout();
    disconnectServicesOnLogout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  void _navigateToChatScreen(Conversation conversation) {
    // Optimistically update the UI to clear the unread count immediately
    if (mounted && conversation.unreadCount > 0) {
      setState(() {
        final index = _conversations.indexWhere((c) => c.id == conversation.id);
        if (index != -1) {
          _conversations[index].unreadCount = 0;
        }
      });
    }

    User? otherUser;
    if (!conversation.isGroupChat &&
        authService.currentUser != null &&
        conversation.participants.isNotEmpty) {
      try {
        otherUser = conversation.participants.firstWhere(
          (p) => p.id != authService.currentUser!.id,
          orElse: () => conversation.participants.first,
        );
      } catch (e) {
        otherUser =
            conversation.participants.isNotEmpty
                ? conversation.participants.first
                : null;
      }
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder:
                (context) => ChatScreen(
                  conversation: conversation,
                  otherUser:
                      otherUser ??
                      User(
                        id: '',
                        fullName: conversation.groupName ?? 'Group',
                        email: '',
                      ),
                ),
          ),
        )
        .then((_) {
          // Upon returning, refresh list to get authoritative counts from server.
          _fetchConversations();
        });
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final localDateTime = dateTime.toLocal();
    if (now.year == localDateTime.year &&
        now.month == localDateTime.month &&
        now.day == localDateTime.day)
      return DateFormat.jm().format(localDateTime);
    if (now.year == localDateTime.year &&
        now.month == localDateTime.month &&
        now.day - localDateTime.day == 1)
      return 'Yesterday';
    if (now.difference(localDateTime).inDays < 7 &&
        now.weekday > localDateTime.weekday)
      return DateFormat.E().format(localDateTime);
    return DateFormat('dd/MM/yy').format(localDateTime);
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        itemCount: 8,
        itemBuilder:
            (_, __) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const CircleAvatar(radius: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 150.0,
                          height: 16.0,
                          color: Colors.white,
                          margin: const EdgeInsets.only(bottom: 6),
                        ),
                        Container(
                          width: double.infinity,
                          height: 12.0,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum_outlined, size: 100, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              'No Conversations Yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Tap the "+" button below to find friends and start chatting.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList() {
    if (_isLoadingConversations) return _buildShimmerLoading();
    if (_errorMessage != null)
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchConversations,
                child: const Text("Retry"),
              ),
            ],
          ),
        ),
      );
    if (_conversations.isEmpty) return _buildEmptyState();

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      itemCount: _conversations.length,
      separatorBuilder:
          (context, index) => Divider(
            height: 1,
            indent: 84,
            endIndent: 16,
            color: Theme.of(context).dividerColor.withOpacity(0.15),
          ),
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        User? displayUserForAvatar;
        String displayName;
        String? displayImageUrl;
        bool isUserOnline = false;
        int unreadCount = conversation.unreadCount;

        if (conversation.isGroupChat) {
          displayName = conversation.groupName ?? 'Group Chat';
          displayImageUrl = conversation.groupPictureUrl;
        } else if (authService.currentUser != null &&
            conversation.participants.isNotEmpty) {
          try {
            displayUserForAvatar = conversation.participants.firstWhere(
              (p) => p.id != authService.currentUser!.id,
            );
            displayName = displayUserForAvatar.fullName;
            displayImageUrl = displayUserForAvatar.profilePictureUrl;
            isUserOnline = _activeUserIds.contains(displayUserForAvatar.id);
          } catch (e) {
            displayName = "Private Chat";
          }
        } else {
          displayName = "Private Chat";
        }

        final lastMsg = conversation.lastMessage;
        String lastMessageText = lastMsg?.content ?? 'Tap to start chatting!';
        if (lastMsg != null &&
            lastMsg.sender.id == authService.currentUser?.id) {
          lastMessageText = "You: $lastMessageText";
        }

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          leading: UserAvatar(
            imageUrl: displayImageUrl,
            userName: displayName,
            radius: 28,
            isActive: isUserOnline,
          ),
          title: Text(
            displayName,
            style: TextStyle(
              fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
              fontSize: 16,
              color: unreadCount > 0 ? Colors.black87 : Colors.grey[800],
            ),
          ),
          subtitle: Text(
            lastMessageText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color:
                  unreadCount > 0
                      ? Theme.of(context).primaryColor
                      : Colors.grey[600],
              fontSize: 14.5,
              fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (lastMsg != null)
                Text(
                  _formatTimestamp(lastMsg.createdAt),
                  style: TextStyle(
                    fontSize: 12.5,
                    color:
                        unreadCount > 0
                            ? Theme.of(context).primaryColor
                            : Colors.grey[500],
                  ),
                ),
              if (lastMsg != null && unreadCount > 0) ...[
                const SizedBox(height: 6),
                CircleAvatar(
                  radius: 10,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(
                    unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ] else
                const SizedBox(height: 26),
            ],
          ),
          onTap: () => _navigateToChatScreen(conversation),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'My Profile',
            onPressed:
                () => Navigator.of(context).pushNamed(ProfileScreen.routeName),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext dialogContext) {
                  return AlertDialog(
                    title: const Text('Confirm Logout'),
                    content: const Text('Are you sure you want to log out?'),
                    actions: <Widget>[
                      TextButton(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      TextButton(
                        child: Text(
                          'Logout',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          _logoutUser();
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchConversations,
        child: _buildConversationList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).pushNamed(UserListScreen.routeName);
        },
        tooltip: 'Start a new chat',
        child: const Icon(Icons.add_comment_outlined),
      ),
    );
  }
}
