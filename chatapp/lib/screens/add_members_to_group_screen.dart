// lib/screens/add_members_to_group_screen.dart
import 'package:flutter/material.dart';
import '../services/services_locator.dart';
import '../models/user_model.dart';
import '../models/conversation_model.dart'; // To update after adding members
import '../widgets/user_avatar.dart';

class AddMembersToGroupScreen extends StatefulWidget {
  final Conversation currentGroup;

  const AddMembersToGroupScreen({super.key, required this.currentGroup});

  @override
  State<AddMembersToGroupScreen> createState() =>
      _AddMembersToGroupScreenState();
}

class _AddMembersToGroupScreenState extends State<AddMembersToGroupScreen> {
  List<User> _allPotentialMembers = [];
  final Set<User> _selectedUsersToAdd = {};
  bool _isLoading = true;
  String? _errorMessage;
  bool _isAddingMembers = false;

  String _searchQuery = '';
  List<User> _filteredPotentialMembers = [];

  @override
  void initState() {
    super.initState();
    _fetchPotentialMembers();
  }

  Future<void> _fetchPotentialMembers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final allUsers =
          await userService
              .getAllUsers(); // Fetches all users (excluding current user)
      final existingMemberIds =
          widget.currentGroup.participants.map((p) => p.id).toSet();

      // Filter out users who are already members of the group
      final potentialMembers =
          allUsers
              .where((user) => !existingMemberIds.contains(user.id))
              .toList();

      if (mounted) {
        setState(() {
          _allPotentialMembers = potentialMembers;
          _filteredPotentialMembers = potentialMembers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst("Exception: ", "");
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _filteredPotentialMembers =
          _allPotentialMembers
              .where(
                (user) =>
                    user.fullName.toLowerCase().contains(query.toLowerCase()) ||
                    user.email.toLowerCase().contains(query.toLowerCase()),
              )
              .toList();
    });
  }

  void _toggleUserSelection(User user) {
    setState(() {
      if (_selectedUsersToAdd.contains(user)) {
        _selectedUsersToAdd.remove(user);
      } else {
        _selectedUsersToAdd.add(user);
      }
    });
  }

  Future<void> _addSelectedMembers() async {
    if (_selectedUsersToAdd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one user to add.'),
        ),
      );
      return;
    }

    setState(() {
      _isAddingMembers = true;
    });

    // Backend expects a single userId to add at a time with the current route.
    // We need to call the API for each selected user.
    // Or, modify backend to accept an array of users to add.
    // For now, let's assume we add them one by one or the first selected one for simplicity.
    // A better approach would be a backend endpoint that takes an array of user IDs to add.
    //
    // Let's iterate and add one by one for this example.
    // We'll collect results and then decide how to update UI.

    List<String> successfullyAddedNames = [];
    List<String> failedToAddNames = [];
    Conversation? lastUpdatedConversation =
        widget.currentGroup; // Start with current

    for (User userToAdd in _selectedUsersToAdd) {
      try {
        // The backend route /add-member takes one userId at a time.
        lastUpdatedConversation = await chatService.addMemberToGroup(
          conversationId: widget.currentGroup.id,
          userIdToAdd: userToAdd.id,
        );
        successfullyAddedNames.add(userToAdd.fullName);
      } catch (e) {
        failedToAddNames.add(userToAdd.fullName);
        print("Failed to add ${userToAdd.fullName}: $e");
      }
    }

    if (mounted) {
      setState(() {
        _isAddingMembers = false;
      });
      String message = "";
      if (successfullyAddedNames.isNotEmpty) {
        message += "Added: ${successfullyAddedNames.join(', ')}. ";
      }
      if (failedToAddNames.isNotEmpty) {
        message += "Failed to add: ${failedToAddNames.join(', ')}. ";
      }
      if (message.isEmpty) {
        message =
            "No members were processed."; // Should not happen if selection is not empty
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.trim()),
          backgroundColor:
              failedToAddNames.isEmpty ? Colors.green : Colors.orange,
        ),
      );

      if (successfullyAddedNames.isNotEmpty &&
          lastUpdatedConversation != null) {
        // Pass back the last known state of the conversation
        Navigator.of(context).pop(lastUpdatedConversation);
      } else if (successfullyAddedNames.isEmpty &&
          failedToAddNames.isNotEmpty) {
        // No successful additions, just pop
        Navigator.of(context).pop();
      } else {
        // No selections or other odd state
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add to "${widget.currentGroup.groupName ?? "Group"}"'),
        actions: [
          if (_selectedUsersToAdd.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Center(
                child: Text(
                  'Add (${_selectedUsersToAdd.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search users to add...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
          ),
          Expanded(child: _buildPotentialMemberList()),
        ],
      ),
      floatingActionButton:
          _selectedUsersToAdd.isNotEmpty
              ? FloatingActionButton.extended(
                onPressed: _isAddingMembers ? null : _addSelectedMembers,
                icon:
                    _isAddingMembers
                        ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : const Icon(Icons.person_add_alt_1_rounded, size: 20),
                label: Text(_isAddingMembers ? 'Adding...' : 'Add Selected'),
              )
              : null,
    );
  }

  Widget _buildPotentialMemberList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null)
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );

    final usersToList =
        _searchQuery.isEmpty ? _allPotentialMembers : _filteredPotentialMembers;

    if (usersToList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _searchQuery.isEmpty
                ? 'All users are already in this group or no other users available.'
                : 'No users found matching your search.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: usersToList.length,
      itemBuilder: (context, index) {
        final user = usersToList[index];
        final bool isSelected = _selectedUsersToAdd.contains(user);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: UserAvatar(
            imageUrl: user.profilePictureUrl,
            userName: user.fullName,
            radius: 24,
          ),
          title: Text(
            user.fullName,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(user.email),
          trailing: Checkbox(
            value: isSelected,
            onChanged: (bool? value) => _toggleUserSelection(user),
            activeColor: Theme.of(context).primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          onTap: () => _toggleUserSelection(user),
        );
      },
    );
  }
}
