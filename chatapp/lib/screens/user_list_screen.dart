// lib/screens/user_list_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/services_locator.dart';
import '../models/user_model.dart';
import '../models/conversation_model.dart';
import 'chat_screen.dart';
import '../widgets/user_avatar.dart';
import 'select_group_members_screen.dart'; // For starting group creation

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});
  static const String routeName = '/user-list';

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  List<User> _allUsers = []; // All users fetched
  // _selectedUsersForGroup is removed as this screen now primarily focuses on 1-to-1
  bool _isLoading = true;
  String? _errorMessage;
  Set<String> _activeUserIds = {};
  StreamSubscription? _activeUsersSubscription;

  String _searchQuery = '';
  List<User> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    // Subscribe to active users if socket is already connected
    // Socket connection is typically initiated after login or on app start if token exists
    if (socketService.socket != null && socketService.socket!.connected) {
      _subscribeToActiveUsers();
    } else {
      // If socket isn't connected yet, it might connect shortly.
      // A more robust approach would be to listen to a socket connection status stream.
      // For now, if _fetchUsers completes and socket is connected, it will try to subscribe.
      print(
        "UserListScreen initState: Socket not immediately connected. Will try subscribing after fetching users if connected then.",
      );
    }
  }

  void _subscribeToActiveUsers() {
    // Cancel any existing subscription to avoid duplicates if _subscribeToActiveUsers is called multiple times
    _activeUsersSubscription?.cancel();
    _activeUsersSubscription = socketService.activeUsersStream.listen(
      (activeIds) {
        if (mounted) {
          setState(() {
            _activeUserIds = activeIds.toSet();
          });
          print(
            "UserListScreen: Active users updated - Count: ${_activeUserIds.length}",
          );
        }
      },
      onError: (error) {
        print("UserListScreen: Error listening to active users stream: $error");
        // Optionally, retry subscription or handle error
      },
    );
    print("UserListScreen: Subscribed to active users updates.");
  }

  @override
  void dispose() {
    _activeUsersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final users = await userService.getAllUsers();
      if (mounted) {
        setState(() {
          _allUsers = users;
          _filteredUsers = users; // Initialize filtered list with all users
          _isLoading = false;
        });
        // Attempt to subscribe to active users if not already, and socket is now connected
        if (socketService.socket != null &&
            socketService.socket!.connected &&
            _activeUsersSubscription == null) {
          _subscribeToActiveUsers();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst("Exception: ", "");
          _isLoading = false;
        });
      }
      print("UserListScreen: Error fetching users: $e");
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredUsers = _allUsers; // If search is empty, show all users
      } else {
        _filteredUsers =
            _allUsers
                .where(
                  (user) =>
                      user.fullName.toLowerCase().contains(
                        query.toLowerCase(),
                      ) ||
                      user.email.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
      }
    });
  }

  // This method is now specifically for starting a ONE-TO-ONE chat
  Future<void> _startOneToOneChat(User otherUser) async {
    if (authService.currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              "Error: Current user not identified. Please re-login.",
            ),
          ),
        );
      }
      return;
    }

    // Show a loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Starting chat..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      // This API call will find an existing 1-to-1 conversation or create a new one.
      final Conversation conversation = await chatService
          .createOrGetOneToOneConversation(otherUser.id);

      if (mounted) {
        Navigator.of(context).pop(); // Dismiss loading indicator
        // For 1-to-1, replace UserListScreen with ChatScreen for a cleaner back stack.
        // This means pressing back from ChatScreen will go to HomeScreen, not back to UserListScreen.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (context) => ChatScreen(
                  conversation: conversation,
                  otherUser: otherUser,
                ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Dismiss loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              "Could not start chat: ${e.toString().replaceFirst("Exception: ", "")}",
            ),
          ),
        );
      }
      print(
        "UserListScreen: Error creating/getting 1-to-1 conversation with ${otherUser.fullName}: $e",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Find Users / New Group',
        ), // Updated title to reflect dual purpose possibility
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'Create New Group',
            onPressed: () {
              // Navigate to the screen where users can be selected for a group
              Navigator.of(
                context,
              ).pushNamed(SelectGroupMembersScreen.routeName);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: TextField(
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText:
                    'Search users to start a chat...', // Updated hint text
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    12.0,
                  ), // Consistent rounding
                  borderSide: BorderSide.none, // Cleaner look
                ),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor.withAlpha(
                  240,
                ), // Slightly different from main scaffold for depth
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ), // Adjust padding for TextField height
              ),
            ),
          ),
          Expanded(child: _buildUserList()),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error,
                size: 50,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                onPressed: _fetchUsers,
              ),
            ],
          ),
        ),
      );
    }

    // Determine which list to display based on search query
    final List<User> usersToDisplay =
        _searchQuery.isEmpty ? _allUsers : _filteredUsers;

    if (usersToDisplay.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            _searchQuery.isEmpty
                ? 'No other users found.'
                : 'No users match your search for "$_searchQuery".',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, color: Colors.grey[600]),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchUsers, // Allow pull-to-refresh
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        itemCount: usersToDisplay.length,
        separatorBuilder:
            (context, index) => Divider(
              height: 1,
              indent: 80, // Indent to align after avatar
              endIndent: 16,
              color: Theme.of(context).dividerColor.withOpacity(0.4),
            ),
        itemBuilder: (context, index) {
          final user = usersToDisplay[index];
          final bool isActive = _activeUserIds.contains(user.id);

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 10.0,
            ),
            leading: UserAvatar(
              imageUrl: user.profilePictureUrl,
              userName: user.fullName,
              isActive: isActive,
              radius: 28,
              borderWidth: 2.0,
              borderColor:
                  Theme.of(
                    context,
                  ).scaffoldBackgroundColor, // Border for active indicator
            ),
            title: Text(
              user.fullName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16.5,
              ),
            ),
            subtitle: Text(
              user.email,
              style: TextStyle(color: Colors.grey[600], fontSize: 13.5),
            ),
            trailing: Icon(
              Icons
                  .chat_bubble_outline_rounded, // Icon indicating "tap to chat"
              color: Theme.of(context).primaryColor,
              size: 22,
            ),
            onTap:
                () => _startOneToOneChat(
                  user,
                ), // This now directly initiates a 1-to-1 chat
          );
        },
      ),
    );
  }
}
