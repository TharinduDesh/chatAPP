// lib/screens/select_group_members_screen.dart
import 'package:flutter/material.dart';
import '../services/services_locator.dart';
import '../models/user_model.dart';
import '../widgets/user_avatar.dart';
import 'create_group_details_screen.dart';

class SelectGroupMembersScreen extends StatefulWidget {
  const SelectGroupMembersScreen({super.key});
  static const String routeName = '/select-group-members';

  @override
  State<SelectGroupMembersScreen> createState() =>
      _SelectGroupMembersScreenState();
}

class _SelectGroupMembersScreenState extends State<SelectGroupMembersScreen> {
  List<User> _allUsers = [];
  final Set<User> _selectedUsers = {}; // Use a Set to store selected users
  bool _isLoading = true;
  String? _errorMessage;

  // For search functionality
  String _searchQuery = '';
  List<User> _filteredUsers = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final users =
          await userService
              .getAllUsers(); // Fetches users excluding current one
      if (mounted) {
        setState(() {
          _allUsers = users;
          _filteredUsers = users; // Initialize filtered list
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
      _filteredUsers =
          _allUsers
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
      if (_selectedUsers.contains(user)) {
        _selectedUsers.remove(user);
      } else {
        _selectedUsers.add(user);
      }
    });
  }

  void _proceedToNext() {
    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one member for the group.'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => CreateGroupDetailsScreen(
              selectedMembers: _selectedUsers.toList(),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Members'),
        actions: [
          if (_selectedUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Center(
                child: Text(
                  '${_selectedUsers.length} selected',
                  style: const TextStyle(fontSize: 16),
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
                hintText: 'Search users...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor:
                    Theme.of(
                      context,
                    ).scaffoldBackgroundColor, // or Colors.grey[200]
              ),
            ),
          ),
          Expanded(child: _buildUserList()),
        ],
      ),
      floatingActionButton:
          _selectedUsers.isNotEmpty
              ? FloatingActionButton.extended(
                onPressed: _proceedToNext,
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                label: const Text('Next'),
              )
              : null,
    );
  }

  Widget _buildUserList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    if (_filteredUsers.isEmpty && _searchQuery.isNotEmpty) {
      return const Center(child: Text('No users found matching your search.'));
    }
    if (_allUsers.isEmpty) {
      return const Center(
        child: Text('No other users available to add to a group.'),
      );
    }

    final usersToList = _searchQuery.isEmpty ? _allUsers : _filteredUsers;

    return ListView.builder(
      itemCount: usersToList.length,
      itemBuilder: (context, index) {
        final user = usersToList[index];
        final bool isSelected = _selectedUsers.contains(user);
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
            onChanged: (bool? value) {
              _toggleUserSelection(user);
            },
            activeColor: Theme.of(context).primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          onTap: () {
            _toggleUserSelection(user);
          },
        );
      },
    );
  }
}
