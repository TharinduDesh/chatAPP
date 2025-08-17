// lib/services/service_locator.dart
import 'auth_service.dart';
import 'socket_service.dart';
import 'user_services.dart';
import 'chat_service.dart';
// ADD THIS IMPORT
import 'biometric_service.dart';

// Global instances - for simplicity in this example.
// Consider using a proper DI/Service Locator package for larger apps (GetIt, Provider, Riverpod).

final AuthService authService = AuthService();
// UserService needs to be available for AuthService's fetchAndSetCurrentUser
final UserService userService = UserService();
// SocketService needs AuthService to get the current user ID for connection.
final SocketService socketService = SocketService(authService);
final ChatService chatService = ChatService();
// ADD THIS LINE: Instantiate the new service
final BiometricService biometricService = BiometricService();

// Call this function in main.dart after user logs in or on app start if token exists.
Future<void> initializeServicesOnLogin() async {
  print("ServiceLocator: initializeServicesOnLogin called.");
  // Ensure current user data is loaded before attempting to connect socket.
  // This is especially important if the app was restarted and only a token exists.
  // authService.fetchAndSetCurrentUser() will attempt to load the user
  // using userService.getUserProfile() if _currentUser is null but a token exists.
  await authService.fetchAndSetCurrentUser();

  if (authService.currentUser != null) {
    print(
      "ServiceLocator: CurrentUser is available (ID: ${authService.currentUser!.id}, Name: ${authService.currentUser!.fullName}). Connecting socket.",
    );
    // Connect socket only after user context is established.
    socketService.connect();
  } else {
    print(
      "ServiceLocator: Cannot connect socket because authService.currentUser is null after fetch attempt.",
    );
    // This could happen if the token is invalid or user data couldn't be fetched.
    // authService.fetchAndSetCurrentUser() should handle logging out if token is invalid.
  }
}

void disconnectServicesOnLogout() {
  print("ServiceLocator: disconnectServicesOnLogout called.");
  socketService.disconnect();
  // ADD THIS LINE: Clear saved credentials on logout
  biometricService.deleteCredentials();
  // You might also want to clear other service states here if necessary.
  // authService.logout() already clears its own _currentUser.
}
