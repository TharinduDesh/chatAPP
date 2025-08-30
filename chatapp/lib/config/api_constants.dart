// lib/config/api_constants.dart

// If you are running the backend on your local machine and testing on an Android emulator,
// use 10.0.2.2 instead of localhost for the server address.
// For iOS simulator or web, localhost should work.
// Make sure your backend server (Node.js) is running on port 5001 (or whatever you configured).

// const String SERVER_ROOT_URL = 'http://10.0.2.2:5000'; // For Android Emulator
// const String SERVER_ROOT_URL = 'http://localhost:5000'; // For iOS Simulator / Web

const String SERVER_ROOT_URL =
    'https://chatapp-production-1bb9.up.railway.app'; // Host

const String API_BASE_URL = '$SERVER_ROOT_URL/api'; // API calls will use this
