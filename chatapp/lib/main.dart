// lib/main.dart
import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/user_list_screen.dart';
import 'screens/select_group_members_screen.dart';
// import 'screens/create_group_details_screen.dart';
// import 'screens/chat_screen.dart';
import 'services/token_storage_service.dart';
import 'services/services_locator.dart';

Future<void> mainApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  final TokenStorageService tokenStorageService = TokenStorageService();
  String? token = await tokenStorageService.getToken();

  if (token != null && token.isNotEmpty) {
    await initializeServicesOnLogin();
  }
  runApp(MyApp(initialToken: token));
}

void main() {
  mainApp();
}

class MyApp extends StatelessWidget {
  final String? initialToken;
  const MyApp({super.key, this.initialToken});

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF0E3B7B);

    final ThemeData appTheme = ThemeData(
      // Use fromSeed to generate a full, harmonious color scheme from your blue color
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.light, // Keep the light theme
      ),
      useMaterial3: true,
      fontFamily: 'Inter',

      scaffoldBackgroundColor: Colors.grey[100],

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 16.0,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Colors.grey[350]!, width: 1.0),
        ),
        // Use the new primary color for the focused border
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: primaryBlue, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Colors.red[600]!, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Colors.red[700]!, width: 1.8),
        ),
        labelStyle: TextStyle(
          color: Colors.grey[700],
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(color: Colors.grey[500]),
        prefixIconColor: Colors.grey[600],
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
            letterSpacing: 0.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
          ),
          elevation: 2,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryBlue, // Use the new primary color
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 1.0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),

      dialogTheme: DialogTheme(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        backgroundColor: Colors.white,
        elevation: 5,
        titleTextStyle: TextStyle(
          color: primaryBlue.withBlue(
            100,
          ), // A slightly adjusted blue for titles
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: 'Inter',
        ),
        contentTextStyle: TextStyle(
          color: Colors.grey[800],
          fontSize: 16,
          fontFamily: 'Inter',
          height: 1.4,
        ),
      ),

      cardTheme: CardTheme(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: BorderSide(color: Colors.grey[200]!, width: 0.8),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: primaryBlue.withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 4.0,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
        ),
        elevation: 5,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        elevation: 4,
        contentTextStyle: const TextStyle(
          fontFamily: 'Inter',
          color: Colors.white,
          fontSize: 15,
        ),
      ),
    );

    return MaterialApp(
      title: 'Modern Chat App',
      theme: appTheme,
      initialRoute:
          initialToken != null && initialToken!.isNotEmpty
              ? HomeScreen.routeName
              : LoginScreen.routeName,
      routes: {
        LoginScreen.routeName: (context) => const LoginScreen(),
        SignupScreen.routeName: (context) => const SignupScreen(),
        HomeScreen.routeName: (context) => const HomeScreen(),
        ProfileScreen.routeName: (context) => const ProfileScreen(),
        UserListScreen.routeName: (context) => const UserListScreen(),
        SelectGroupMembersScreen.routeName:
            (context) => const SelectGroupMembersScreen(), // <<< Added route
        // CreateGroupDetailsScreen is typically navigated to directly with arguments (using MaterialPageRoute)
        // rather than by a named route, because it requires the 'selectedMembers' list.
        // If you were to use named routes for it, you'd need to handle argument passing via settings in onGenerateRoute.
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
