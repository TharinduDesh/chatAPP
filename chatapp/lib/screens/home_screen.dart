// lib/screens/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../services/services_locator.dart';
import '../models/conversation_model.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'user_list_screen.dart';
import 'chat_screen.dart';
import '../widgets/user_avatar.dart';
import '../services/crypto_service.dart';
import '../services/cache_service.dart';
import '../services/socket_service.dart';

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
  final CryptoService _cryptoService = CryptoService();
  final CacheService _cacheService = CacheService();

  StreamSubscription? _conversationUpdateSubscription;
  StreamSubscription? _newMessageSubscription;
  StreamSubscription? _activeUsersSubscription;
  Set<String> _activeUserIds = {};

  @override
  void initState() {
    super.initState();

    // ==================  START: UPDATED LOGIN FLOW  ==================
    // 1. Re-initialize the service to ensure all streams are fresh.
    socketService.init();
    // 2. Now, tell the service to connect.
    socketService.connect();
    // ===================  END: UPDATED LOGIN FLOW  ===================

    _loadInitialData();
    _searchController.addListener(_filterConversations);
    _subscribeToSocketEvents();
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

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoadingConversations = true;
    });

    final cachedConversations = _cacheService.getConversations();
    if (cachedConversations.isNotEmpty) {
      final decryptedCachedConvos = await _decryptConversationList(
        cachedConversations,
      );
      setState(() {
        _conversations = decryptedCachedConvos;
        _filteredConversations = decryptedCachedConvos;
        _isLoadingConversations = false;
      });
    }

    await _fetchConversationsFromServer();
  }

  void _subscribeToSocketEvents() {
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
                _filterConversations();
              });
            } else {
              setState(() {
                _conversations.insert(0, updatedConv);
                _conversations.sort(
                  (a, b) => b.updatedAt.compareTo(a.updatedAt),
                );
                _filterConversations();
              });
            }
          }
        });

    _newMessageSubscription = socketService.messageStream.listen((
      message,
    ) async {
      if (mounted) {
        final int conversationIndex = _conversations.indexWhere(
          (c) => c.id == message.conversationId,
        );
        if (conversationIndex != -1) {
          Message messageToShow = message;
          Conversation conversation = _conversations[conversationIndex];

          if (message.isEncrypted) {
            await _cryptoService.ready;
            String? decryptedContent;
            if (conversation.isGroupChat) {
              decryptedContent = await _cryptoService.decryptGroupMessage(
                conversation.id,
                message.content,
              );
            } else {
              final otherUser = conversation.getOtherParticipant(
                authService.currentUser!.id,
              );
              if (otherUser != null) {
                decryptedContent = await _cryptoService.decrypt1on1Message(
                  otherUser.id,
                  message.content,
                );
              }
            }
            messageToShow = message.copyWith(
              content: decryptedContent ?? '[Encrypted Message]',
            );
          }

          setState(() {
            Conversation oldConv = _conversations[conversationIndex];
            bool shouldIncrementUnread = false;
            if (messageToShow.sender != null) {
              shouldIncrementUnread =
                  messageToShow.sender!.id != authService.currentUser?.id;
            }
            _conversations[conversationIndex] = oldConv.copyWith(
              lastMessage: messageToShow,
              updatedAt: messageToShow.createdAt,
              unreadCount:
                  shouldIncrementUnread
                      ? (oldConv.unreadCount) + 1
                      : oldConv.unreadCount,
            );

            _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            _filterConversations();
          });
        } else {
          _fetchConversationsFromServer();
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

  Future<void> _fetchConversationsFromServer() async {
    if (authService.currentUser == null) {
      if (mounted && _conversations.isEmpty) {
        setState(() {
          _errorMessage = "Not logged in.";
          _isLoadingConversations = false;
        });
      }
      return;
    }

    try {
      final conversationsFromServer = await chatService.getConversations();
      final decryptedConversations = await _decryptConversationList(
        conversationsFromServer,
      );

      await _cacheService.saveConversations(decryptedConversations);

      if (mounted) {
        setState(() {
          _conversations = decryptedConversations;
          _filteredConversations = decryptedConversations;
          _isLoadingConversations = false;
          _errorMessage = null;
          _filterConversations();
        });
      }
    } catch (e) {
      if (mounted && _conversations.isEmpty) {
        setState(() {
          _errorMessage = e.toString().replaceFirst("Exception: ", "");
          _isLoadingConversations = false;
        });
      }
    }
  }

  // NOTE: The "_handleRefresh" method has been removed as it's no longer needed.

  Future<List<Conversation>> _decryptConversationList(
    List<Conversation> convos,
  ) async {
    await _cryptoService.ready;
    final currentUserId = authService.currentUser!.id;

    return Future.wait(
      convos.map((convo) async {
        final lastMsg = convo.lastMessage;

        if (lastMsg != null && lastMsg.isEncrypted) {
          String? decryptedContent;

          if (convo.isGroupChat) {
            decryptedContent = await _cryptoService.decryptGroupMessage(
              convo.id,
              lastMsg.content,
            );
          } else {
            final otherUser = convo.getOtherParticipant(currentUserId);
            if (otherUser != null) {
              decryptedContent = await _cryptoService.decrypt1on1Message(
                otherUser.id,
                lastMsg.content,
              );
            }
          }

          if (decryptedContent != null) {
            final decryptedMessage = lastMsg.copyWith(
              content: decryptedContent,
            );
            return convo.copyWith(lastMessage: decryptedMessage);
          }
        }
        return convo;
      }).toList(),
    );
  }

  // ==================  START: UPDATED LOGOUT FLOW  ==================
  Future<void> _logoutUser() async {
    // 1. Completely dispose of the service state before logging out.
    socketService.dispose();

    // 2. Continue with the original logout process.
    await authService.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }
  // ===================  END: UPDATED LOGOUT FLOW  ===================

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
          _fetchConversationsFromServer();
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
    if (_isLoadingConversations && _conversations.isEmpty) {
      return _buildShimmerLoading();
    }
    if (_errorMessage != null && _conversations.isEmpty) {
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
                onPressed: _fetchConversationsFromServer,
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

  Widget _buildConnectionStatusIndicator() {
    return StreamBuilder<SocketStatus>(
      stream: socketService.connectionStatusStream,
      initialData: socketService.lastStatus,
      builder: (context, snapshot) {
        if (snapshot.data == SocketStatus.online) {
          return const SizedBox.shrink();
        }

        return Material(
          child: Container(
            width: double.infinity,
            color: Colors.grey[600]!,
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
          _buildConnectionStatusIndicator(),
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
              // NOTE: Reverted to the original function.
              onRefresh: _fetchConversationsFromServer,
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
