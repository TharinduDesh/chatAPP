// lib/screens/create_group_details_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/services_locator.dart';
import '../models/user_model.dart';
import '../models/conversation_model.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart'; // To navigate to the newly created group chat

class CreateGroupDetailsScreen extends StatefulWidget {
  final List<User> selectedMembers;

  const CreateGroupDetailsScreen({super.key, required this.selectedMembers});

  @override
  State<CreateGroupDetailsScreen> createState() =>
      _CreateGroupDetailsScreenState();
}

class _CreateGroupDetailsScreenState extends State<CreateGroupDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _groupNameController = TextEditingController();
  File? _groupImageFile;
  final ImagePicker _picker = ImagePicker();
  bool _isCreatingGroup = false;

  Future<void> _pickGroupImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery, // Or allow camera ImageSource.camera
        maxWidth: 800,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _groupImageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot create a group with no members selected (excluding yourself).',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isCreatingGroup = true;
    });

    try {
      final List<String> memberIds =
          widget.selectedMembers.map((user) => user.id).toList();

      // Current user is added as admin on the backend, no need to add explicitly here to memberIds unless backend logic changes
      print(
        "FLUTTER_DEBUG: Creating group with name: '${_groupNameController.text.trim()}' and participant IDs: $memberIds",
      );
      for (var user in widget.selectedMembers) {
        print(
          "FLUTTER_DEBUG: Selected User: ${user.fullName}, ID: ${user.id}, Email: ${user.email}",
        );
      }

      Conversation createdConversation = await chatService
          .createGroupConversation(
            name: _groupNameController.text.trim(),
            participantIds: memberIds,
          );

      // If an image was selected, upload it
      if (_groupImageFile != null) {
        try {
          createdConversation = await chatService.uploadGroupPicture(
            conversationId: createdConversation.id,
            imageFile: _groupImageFile!,
          );
          print(
            "Group picture uploaded successfully for ${createdConversation.id}",
          );
        } catch (e) {
          print("Failed to upload group picture: $e");
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Group created, but failed to upload group picture: $e',
                ),
                backgroundColor: Colors.orange,
              ),
            );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Group "${createdConversation.groupName}" created successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate to the new chat screen, removing previous group creation screens from stack
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder:
                (context) => ChatScreen(
                  conversation: createdConversation,
                  // For groups, otherUser is less relevant for AppBar title, ChatScreen should use conversation.groupName
                  // Pass a representative user or a dummy if ChatScreen expects a non-null otherUser.
                  // Ideally ChatScreen adapts based on conversation.isGroupChat
                  otherUser: User(
                    id: '',
                    fullName: createdConversation.groupName ?? 'Group',
                    email: '',
                  ),
                ),
          ),
          (Route<dynamic> route) =>
              route
                  .isFirst, // Remove all routes until the first one (HomeScreen)
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create group: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted)
        setState(() {
          _isCreatingGroup = false;
        });
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Group Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickGroupImage,
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey[300],
                    backgroundImage:
                        _groupImageFile != null
                            ? FileImage(_groupImageFile!)
                            : null,
                    child:
                        _groupImageFile == null
                            ? Icon(
                              Icons.group_add_rounded,
                              size: 50,
                              color: Colors.grey[700],
                            )
                            : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  icon: Icon(
                    _groupImageFile == null
                        ? Icons.add_a_photo_outlined
                        : Icons.edit_outlined,
                    size: 20,
                  ),
                  label: Text(
                    _groupImageFile == null
                        ? 'Add Group Icon'
                        : 'Change Group Icon',
                  ),
                  onPressed: _pickGroupImage,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _groupNameController,
                decoration: InputDecoration(
                  labelText: 'Group Name',
                  hintText: 'Enter group name...',
                  prefixIcon: const Icon(Icons.group_work_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a group name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Members (${widget.selectedMembers.length + 1}):', // +1 for current user (admin)
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              // Display current user (admin)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(
                  userName: authService.currentUser?.fullName ?? "Me",
                  imageUrl: authService.currentUser?.profilePictureUrl,
                  radius: 20,
                ),
                title: Text(
                  "${authService.currentUser?.fullName ?? "Your Name"} (Admin)",
                ),
              ),
              // Display selected members
              SizedBox(
                height:
                    widget.selectedMembers.length *
                    60.0, // Adjust height based on items
                child: ListView.builder(
                  physics:
                      const NeverScrollableScrollPhysics(), // If inside SingleChildScrollView
                  itemCount: widget.selectedMembers.length,
                  itemBuilder: (context, index) {
                    final member = widget.selectedMembers[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: UserAvatar(
                        userName: member.fullName,
                        imageUrl: member.profilePictureUrl,
                        radius: 20,
                      ),
                      title: Text(member.fullName),
                    );
                  },
                ),
              ),
              const SizedBox(height: 30),
              _isCreatingGroup
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Create Group'),
                    onPressed: _createGroup,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
