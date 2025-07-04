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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  static const String routeName = '/home';
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Conversation> _conversations = [];
  List<Conversation> _filteredConversations = [];
  bool _isLoadingConversations = true;
  String? _errorMessage;

  final TextEditingController _searchController = TextEditingController();

  StreamSubscription? _conversationUpdateSubscription;
  StreamSubscription? _newMessageSubscription;
  StreamSubscription? _activeUsersSubscription;
  Set<String> _activeUserIds = {};

  @override
  void initState() {
    super.initState();
    _initializeScreen();
    _searchController.addListener(_filterConversations);

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
                _filterConversations(); // Re-apply filter
              });
            } else {
              setState(() {
                _conversations.insert(0, updatedConv);
                _conversations.sort(
                  (a, b) => b.updatedAt.compareTo(a.updatedAt),
                );
                _filterConversations(); // Re-apply filter
              });
            }
          }
        });

    _newMessageSubscription = socketService.messageStream.listen((newMessage) {
      if (mounted) {
        final int conversationIndex = _conversations.indexWhere(
          (c) => c.id == newMessage.conversationId,
        );
        if (conversationIndex != -1) {
          setState(() {
            Conversation oldConv = _conversations[conversationIndex];
            bool shouldIncrementUnread = false;
            // Only check the sender if it's not a system message.
            if (newMessage.sender != null) {
              shouldIncrementUnread =
                  newMessage.sender!.id != authService.currentUser?.id;
            }
            _conversations[conversationIndex] = Conversation(
              id: oldConv.id,
              participants: oldConv.participants,
              isGroupChat: oldConv.isGroupChat,
              groupName: oldConv.groupName,
              groupAdmins: oldConv.groupAdmins,
              groupPictureUrl: oldConv.groupPictureUrl,
              lastMessage: newMessage,
              createdAt: oldConv.createdAt,
              updatedAt: newMessage.createdAt,
              unreadCount:
                  shouldIncrementUnread
                      ? (oldConv.unreadCount) + 1
                      : oldConv.unreadCount,
            );
            _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            _filterConversations(); // Re-apply filter
          });
        } else {
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

  @override
  void dispose() {
    _conversationUpdateSubscription?.cancel();
    _newMessageSubscription?.cancel();
    _activeUsersSubscription?.cancel();
    _searchController.removeListener(_filterConversations);
    _searchController.dispose();
    super.dispose();
  }

  void _filterConversations() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredConversations =
          _conversations.where((convo) {
            String displayName;
            if (convo.isGroupChat) {
              displayName = convo.groupName ?? '';
            } else {
              final otherUser = convo.getOtherParticipant(
                authService.currentUser!.id,
              );
              displayName = otherUser?.fullName ?? 'Private Chat';
            }
            return displayName.toLowerCase().contains(query);
          }).toList();
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

  Future<void> _fetchConversations() async {
    if (authService.currentUser == null) {
      if (mounted) {
        setState(() {
          _isLoadingConversations = false;
          _errorMessage = "Not logged in.";
        });
      }
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
          _filteredConversations = conversations;
          _isLoadingConversations = false;
          _filterConversations(); // Apply filter on initial fetch
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
    if (mounted && conversation.unreadCount > 0) {
      setState(() {
        final index = _conversations.indexWhere((c) => c.id == conversation.id);
        if (index != -1) {
          _conversations[index].unreadCount = 0;
          _filterConversations();
        }
      });
    }

    User? otherUser =
        conversation.isGroupChat
            ? null
            : conversation.getOtherParticipant(authService.currentUser!.id);

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
          _fetchConversations();
        });
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final localDateTime = dateTime.toLocal();
    if (DateUtils.isSameDay(now, localDateTime)) {
      return DateFormat.jm().format(localDateTime);
    }
    if (DateUtils.isSameDay(
      now.subtract(const Duration(days: 1)),
      localDateTime,
    )) {
      return 'Yesterday';
    }
    if (now.difference(localDateTime).inDays < 7) {
      return DateFormat.E().format(localDateTime);
    }
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

  Widget _buildNoResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              'No Results Found',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'No chats match your search for "${_searchController.text}".',
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
    if (_errorMessage != null) {
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
    }

    if (_filteredConversations.isEmpty) {
      return _conversations.isEmpty ? _buildEmptyState() : _buildNoResults();
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      itemCount: _filteredConversations.length,
      separatorBuilder:
          (context, index) => Divider(
            height: 1,
            indent: 84,
            endIndent: 16,
            color: Theme.of(context).dividerColor.withOpacity(0.15),
          ),
      itemBuilder: (context, index) {
        if (authService.currentUser == null) {
          return const SizedBox.shrink();
        }
        final conversation = _filteredConversations[index];
        final otherUser = conversation.getOtherParticipant(
          authService.currentUser!.id,
        );
        final displayName =
            conversation.isGroupChat
                ? (conversation.groupName ?? 'Group Chat')
                : (otherUser?.fullName ?? 'Private Chat');
        final displayImageUrl =
            conversation.isGroupChat
                ? conversation.groupPictureUrl
                : otherUser?.profilePictureUrl;
        final isUserOnline =
            !conversation.isGroupChat && _activeUserIds.contains(otherUser?.id);
        final unreadCount = conversation.unreadCount;

        final lastMsg = conversation.lastMessage;
        String lastMessageText = 'Tap to start chatting!';
        if (lastMsg != null) {
          if (lastMsg.fileUrl != null && lastMsg.fileUrl!.isNotEmpty) {
            lastMessageText =
                lastMsg.fileType!.startsWith('image')
                    ? '📷 Photo'
                    : (lastMsg.fileType!.startsWith('audio')
                        ? '🎤 Voice Message'
                        : '📎 File');
          } else {
            lastMessageText = lastMsg.content;
          }

          if (lastMsg.sender != null &&
              lastMsg.sender!.id == authService.currentUser?.id) {
            lastMessageText = "You: $lastMessageText";
          }
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
              const SizedBox(height: 4),
              if (unreadCount > 0)
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
                )
              else
                const SizedBox(height: 20),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                        : null,
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchConversations,
              child: _buildConversationList(),
            ),
          ),
        ],
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
