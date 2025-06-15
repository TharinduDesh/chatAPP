// lib/widgets/user_avatar.dart
import 'package:flutter/material.dart';
import '../config/api_constants.dart'; // For SERVER_ROOT_URL to construct full image URLs

class UserAvatar extends StatelessWidget {
  final String? imageUrl; // URL of the user's profile picture
  final String userName; // User's full name, used for initials if no image
  final double radius; // Radius of the CircleAvatar
  final bool isActive; // Whether to display the active (online) indicator
  final Color?
  activeColor; // Color for the active indicator (defaults to green)
  final Color? borderColor; // Color for the border of the active indicator
  final double borderWidth; // Width of the border for the active indicator
  final TextStyle? textStyle; // Custom text style for the initials

  const UserAvatar({
    super.key,
    this.imageUrl,
    required this.userName,
    this.radius = 20.0, // Default radius
    this.isActive = false,
    this.activeColor,
    this.borderColor,
    this.borderWidth = 1.5, // Default border width for the active indicator
    this.textStyle,
  });

  // Helper function to generate initials from a name
  String getInitials(String name) {
    if (name.isEmpty) return '?'; // Fallback for empty name

    // Split the name by spaces to get individual words
    List<String> nameParts = name.trim().split(RegExp(r'\s+'));

    // Filter out any empty strings that might result from multiple spaces
    nameParts = nameParts.where((part) => part.isNotEmpty).toList();

    if (nameParts.isEmpty) return '?'; // Fallback if all parts were empty

    // Take the first letter of the first part
    String initials = nameParts.first.substring(0, 1).toUpperCase();

    // If there's more than one part (e.g., first and last name), take the first letter of the last part
    if (nameParts.length > 1) {
      initials += nameParts.last.substring(0, 1).toUpperCase();
    }
    // If only one part and it's longer than one character, take the second character as well (optional)
    // else if (nameParts.first.length > 1) {
    //   initials += nameParts.first.substring(1, 2).toUpperCase();
    // }
    return initials;
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? backgroundImage;
    bool canDisplayImage =
        false; // Flag to track if an image is expected to be displayed

    // Check if an image URL is provided and is not empty
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      String fullImageUrl = imageUrl!.trim();
      // If the URL is relative (starts with '/'), prepend the server root URL
      if (fullImageUrl.startsWith('/')) {
        fullImageUrl = '$SERVER_ROOT_URL$fullImageUrl';
      }
      backgroundImage = NetworkImage(fullImageUrl);
      canDisplayImage = true; // We have a valid image path to attempt loading
    }

    // Determine the color for the active indicator
    final Color effectiveActiveColor =
        activeColor ?? Colors.greenAccent[700] ?? Colors.green;
    // Determine the border color for the active indicator
    final Color effectiveBorderColor =
        borderColor ??
        Theme.of(context).canvasColor; // canvasColor for a clean separation

    return Stack(
      clipBehavior:
          Clip.none, // Allows the active indicator to slightly overflow if desired
      alignment: Alignment.center,
      children: [
        // Main CircleAvatar for the profile picture or initials
        CircleAvatar(
          radius: radius,
          // Fallback background color if no image or initials
          backgroundColor: Theme.of(
            context,
          ).colorScheme.primaryContainer.withOpacity(0.3),
          backgroundImage: backgroundImage, // Will be null if no valid imageUrl
          // Handle errors when loading the network image
          onBackgroundImageError:
              canDisplayImage // Only set error handler if we attempted to load an image
                  ? (dynamic exception, StackTrace? stackTrace) {
                    print(
                      "UserAvatar: Error loading image '$imageUrl': $exception",
                    );
                    // In a stateful widget, you could setState here to force initials if image load fails
                    // For a stateless widget, the child (initials) will show if backgroundImage is null or fails
                  }
                  : null,
          // Display initials if no image is available or if the image fails to load
          child:
              (!canDisplayImage || backgroundImage == null)
                  ? Text(
                    getInitials(userName),
                    style:
                        textStyle ??
                        TextStyle(
                          fontSize:
                              radius *
                              0.7, // Font size relative to avatar radius
                          fontWeight: FontWeight.bold,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer.withOpacity(0.9),
                        ),
                  )
                  : null, // No child Text if an image is being displayed
        ),
        // Active status indicator (small dot)
        if (isActive)
          Positioned(
            bottom:
                radius *
                0.0, // Adjust positioning as needed (e.g., radius * -0.05 for overlap)
            right: radius * 0.0, // Adjust positioning as needed
            child: Container(
              width:
                  radius *
                  0.55, // Size of the active dot relative to avatar radius
              height: radius * 0.55,
              decoration: BoxDecoration(
                color: effectiveActiveColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: effectiveBorderColor,
                  width:
                      borderWidth, // Width of the border around the active dot
                ),
                boxShadow: [
                  // Optional: add a subtle shadow to the active dot
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 2.0,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
