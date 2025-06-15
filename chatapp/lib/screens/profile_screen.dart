// lib/screens/profile_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/services_locator.dart';
import '../models/user_model.dart';
import 'login_screen.dart';
import '../config/api_constants.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  static const String routeName = '/profile';
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  User? _currentUser;
  File? _pickedImageFile;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    // If navigating here, currentUser in authService should ideally be set.
    // If not (e.g., deep link or unexpected state), _loadUserProfile will fetch it.
    if (authService.currentUser != null) {
      _currentUser = authService.currentUser;
      _fullNameController.text = _currentUser!.fullName;
      _emailController.text = _currentUser!.email;
      setState(() {
        _isLoading = false;
      });
      print(
        "ProfileScreen initState: Using existing currentUser from authService: ${_currentUser!.fullName}",
      );
    } else {
      print(
        "ProfileScreen initState: currentUser is null in authService. Calling _loadUserProfile.",
      );
      _loadUserProfile();
    }
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
      _pickedImageFile = null;
    });
    final result = await userService.getUserProfile();
    if (mounted) {
      if (result['success']) {
        setState(() {
          _currentUser = result['data'] as User;
          authService.setCurrentUser(
            _currentUser,
          ); // Crucial: Update global authService.currentUser
          _fullNameController.text = _currentUser!.fullName;
          _emailController.text = _currentUser!.email;
          _isLoading = false;
        });
        print(
          "ProfileScreen _loadUserProfile: Profile loaded and set: ${_currentUser!.fullName}",
        );
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to load profile.';
          _isLoading = false;
        });
        print("ProfileScreen _loadUserProfile: Error - $_errorMessage");
        if (result['message'] != null &&
            (result['message'].toLowerCase().contains('token') ||
                result['message'].toLowerCase().contains('unauthorized') ||
                result['message'].toLowerCase().contains(
                  'not authenticated',
                ))) {
          _handleLogout(
            showSnackbar: false,
            message: "Session expired. Please log in again.",
          );
        }
      }
    }
  }

  Future<void> _updateProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isSaving = true;
        _errorMessage = null;
        _successMessage = null;
      });
      final result = await userService.updateUserProfile(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        if (result['success']) {
          setState(() {
            _currentUser = result['data'] as User;
            authService.setCurrentUser(
              _currentUser,
            ); // Update global authService.currentUser
            _fullNameController.text = _currentUser!.fullName;
            _emailController.text = _currentUser!.email;
            _successMessage =
                result['message'] ?? 'Profile updated successfully!';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_successMessage!),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          setState(() {
            _errorMessage = result['message'] ?? 'Failed to update profile.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_errorMessage!),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (pickedFile != null) {
        setState(() {
          _pickedImageFile = File(pickedFile.path);
          _errorMessage = null;
        });
        _uploadAvatar();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  Future<void> _uploadAvatar() async {
    if (_pickedImageFile == null) return;
    setState(() {
      _isUploadingAvatar = true;
      _errorMessage = null;
      _successMessage = null;
    });
    final result = await userService.uploadProfilePicture(_pickedImageFile!);
    if (mounted) {
      setState(() {
        _isUploadingAvatar = false;
      });
      if (result['success'] && result['data'] != null) {
        final updatedUserData = result['data']['user'];
        if (updatedUserData != null) {
          setState(() {
            _currentUser = User.fromJson(updatedUserData);
            authService.setCurrentUser(
              _currentUser,
            ); // Update global authService.currentUser
            _pickedImageFile = null;
            _successMessage =
                result['message'] ?? 'Avatar updated successfully!';
          });
        } else {
          _errorMessage = 'Avatar upload response was unclear.';
        }
        if (_successMessage != null)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_successMessage!),
              backgroundColor: Colors.green,
            ),
          );
        else if (_errorMessage != null)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_errorMessage!),
              backgroundColor: Colors.red,
            ),
          );
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to upload avatar.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage!), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photo Library'),
                onTap: () {
                  _pickImage(ImageSource.gallery);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Camera'),
                onTap: () {
                  _pickImage(ImageSource.camera);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileImage() {
    ImageProvider? backgroundImage;
    if (_pickedImageFile != null) {
      backgroundImage = FileImage(_pickedImageFile!);
    } else if (_currentUser?.profilePictureUrl != null &&
        _currentUser!.profilePictureUrl!.isNotEmpty) {
      String imageUrl = _currentUser!.profilePictureUrl!;
      if (imageUrl.startsWith('/')) {
        imageUrl = '$SERVER_ROOT_URL$imageUrl';
      }
      backgroundImage = NetworkImage(imageUrl);
    }

    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.grey[200],
            backgroundImage: backgroundImage,
            onBackgroundImageError:
                backgroundImage != null
                    ? (dynamic exception, StackTrace? stackTrace) {
                      print("Error loading profile image: $exception");
                    }
                    : null,
            child:
                backgroundImage == null
                    ? Icon(
                      Icons.person_outline,
                      size: 60,
                      color: Colors.grey[400],
                    )
                    : null,
          ),
          Positioned(
            bottom: 0,
            right: -4,
            child: CircleAvatar(
              radius: 22,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Theme.of(context).primaryColor,
                child:
                    _isUploadingAvatar
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                        : IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: _showImagePickerOptions,
                          tooltip: 'Change Profile Picture',
                        ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileForm() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _currentUser == null) {
      // Critical error if profile couldn't load
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red[700], size: 50),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red[700], fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                onPressed: _loadUserProfile,
              ),
            ],
          ),
        ),
      );
    }
    if (_currentUser == null) {
      // Fallback
      return const Center(
        child: Text("Profile data is currently unavailable."),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildProfileImage(),
            const SizedBox(height: 30),
            TextFormField(
              controller: _fullNameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty)
                  return 'Please enter your full name';
                return null;
              },
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty)
                  return 'Please enter your email';
                if (!RegExp(
                  r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
                ).hasMatch(value))
                  return 'Please enter a valid email address';
                return null;
              },
            ),
            const SizedBox(height: 30),
            TextButton(
              onPressed:
                  () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Change password functionality coming soon!',
                      ),
                    ),
                  ),
              child: const Text('Change Password'),
            ),
            const SizedBox(height: 20),
            _isSaving
                ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: CircularProgressIndicator(),
                  ),
                )
                : ElevatedButton.icon(
                  icon: const Icon(Icons.save_alt_outlined),
                  onPressed: _updateProfile,
                  label: const Text('Save Changes'),
                ),
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: Icon(Icons.logout, color: Colors.red[700]),
              label: Text('Logout', style: TextStyle(color: Colors.red[700])),
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
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                        TextButton(
                          child: Text(
                            'Logout',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            _handleLogout();
                          },
                        ),
                      ],
                    );
                  },
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[200],
                elevation: 0,
                side: BorderSide(color: Colors.grey[300]!),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout({
    bool showSnackbar = true,
    String? message,
  }) async {
    await authService.logout();
    disconnectServicesOnLogout(); // Disconnect socket and other services
    if (mounted) {
      if (showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message ?? "You have been logged out."),
            backgroundColor: Colors.blue,
          ),
        );
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: _buildProfileForm(),
    );
  }
}
