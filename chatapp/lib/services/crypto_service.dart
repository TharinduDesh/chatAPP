// lib/services/crypto_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import '../config/api_constants.dart';
import 'token_storage_service.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final _secureStorage = const FlutterSecureStorage();
  final _algorithm = X25519();
  final _symmetricAlgorithm = Chacha20.poly1305Aead();
  SimpleKeyPair? _keyPair;

  final Completer<void> _readyCompleter = Completer();
  Future<void> get ready => _readyCompleter.future;

  Future<void> init() async {
    if (_readyCompleter.isCompleted) return;
    try {
      await _loadKeyPair();
      if (_keyPair == null) {
        await generateAndSaveKeyPair();
      }
      _readyCompleter.complete();
      print("✅ CryptoService is ready.");
    } catch (e) {
      _readyCompleter.completeError(e);
      print("❌ CryptoService failed to initialize: $e");
    }
  }

  SimpleKeyPair? getIdentityKeyPair() => _keyPair;

  Future<void> _loadKeyPair() async {
    final privateKeySeed = await _secureStorage.read(
      key: 'e2ee_private_key_seed',
    );
    if (privateKeySeed != null) {
      _keyPair = await _algorithm.newKeyPairFromSeed(
        base64.decode(privateKeySeed),
      );
      print("✅ CryptoService: Key pair loaded from storage.");
    } else {
      print("🔧 CryptoService: No key pair found in storage.");
    }
  }

  Future<void> generateAndSaveKeyPair() async {
    _keyPair = await _algorithm.newKeyPair();
    final privateKeyBytes = await _keyPair!.extractPrivateKeyBytes();
    await _secureStorage.write(
      key: 'e2ee_private_key_seed',
      value: base64.encode(privateKeyBytes),
    );
    print("✅ CryptoService: New key pair generated and saved.");
  }

  Future<String?> getMyPublicKey() async {
    if (_keyPair == null) return null;
    final publicKey = await _keyPair!.extractPublicKey();
    return base64.encode(publicKey.bytes);
  }

  Future<SimplePublicKey> _getPublicKeyForUser(String userId) async {
    final token = await TokenStorageService().getToken();
    final response = await http.get(
      Uri.parse('$API_BASE_URL/keys/$userId/publicKey'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      final publicKeyBytes = base64.decode(
        json.decode(response.body)['publicKey'],
      );
      return SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519);
    }
    throw Exception('Failed to fetch public key for user $userId');
  }

  Future<String?> encryptMessage(String recipientId, String message) async {
    if (_keyPair == null) return null;
    try {
      final recipientPublicKey = await _getPublicKeyForUser(recipientId);
      final sharedSecret = await _algorithm.sharedSecretKey(
        keyPair: _keyPair!,
        remotePublicKey: recipientPublicKey,
      );
      final messageBytes = utf8.encode(message);
      final secretBox = await _symmetricAlgorithm.encrypt(
        messageBytes,
        secretKey: sharedSecret,
      );
      return base64.encode(secretBox.concatenation());
    } catch (e) {
      print("❌ Error during 1-to-1 encryption: $e");
      return null;
    }
  }

  // --- MODIFIED: This function is now correctly named and structured ---
  /// Decrypts a 1-on-1 message. The shared secret is always derived from the other user's public key.
  Future<String?> decrypt1on1Message(
    String otherUserId,
    String encryptedContent,
  ) async {
    if (_keyPair == null) {
      print("❌ Cannot decrypt: local key pair not loaded.");
      return null;
    }
    try {
      final otherUserPublicKey = await _getPublicKeyForUser(otherUserId);
      final sharedSecret = await _algorithm.sharedSecretKey(
        keyPair: _keyPair!,
        remotePublicKey: otherUserPublicKey,
      );
      final encryptedBytes = base64.decode(encryptedContent);
      final secretBox = SecretBox.fromConcatenation(
        encryptedBytes,
        nonceLength: 12,
        macLength: 16,
      );
      final decryptedBytes = await _symmetricAlgorithm.decrypt(
        secretBox,
        secretKey: sharedSecret,
      );
      return utf8.decode(decryptedBytes);
    } catch (e) {
      print("❌ Error during 1-to-1 decryption: $e");
      return "[Error: Could not decrypt]";
    }
  }

  Future<SecretKey> _generateGroupKey() async {
    final keyData = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return SecretKey(keyData);
  }

  Future<SecretKey> getOrGenerateGroupKey(String conversationId) async {
    final keyStorageIdentifier = 'group_key_$conversationId';
    String? storedKey = await _secureStorage.read(key: keyStorageIdentifier);

    if (storedKey != null) {
      print("✅ Found existing group key for $conversationId");
      return SecretKey(base64.decode(storedKey));
    } else {
      print("🔧 No group key found for $conversationId. Generating a new one.");
      final newKey = await _generateGroupKey();
      await _secureStorage.write(
        key: keyStorageIdentifier,
        value: base64.encode(await newKey.extractBytes()),
      );
      return newKey;
    }
  }

  Future<String?> encryptGroupMessage(
    String conversationId,
    String message,
  ) async {
    try {
      final groupKey = await getOrGenerateGroupKey(conversationId);
      final messageBytes = utf8.encode(message);
      final secretBox = await _symmetricAlgorithm.encrypt(
        messageBytes,
        secretKey: groupKey,
      );
      return base64.encode(secretBox.concatenation());
    } catch (e) {
      print("❌ Error during group message encryption: $e");
      return null;
    }
  }

  Future<String?> decryptGroupMessage(
    String conversationId,
    String encryptedContent,
  ) async {
    try {
      final groupKey = await getOrGenerateGroupKey(conversationId);
      final encryptedBytes = base64.decode(encryptedContent);
      final secretBox = SecretBox.fromConcatenation(
        encryptedBytes,
        nonceLength: 12,
        macLength: 16,
      );
      final decryptedBytes = await _symmetricAlgorithm.decrypt(
        secretBox,
        secretKey: groupKey,
      );
      return utf8.decode(decryptedBytes);
    } catch (e) {
      print("❌ Error during group message decryption: $e");
      return "[Error: Could not decrypt group message]";
    }
  }

  Future<String?> encryptGroupKeyForUser(
    SecretKey groupKey,
    String recipientId,
  ) async {
    final keyBytes = await groupKey.extractBytes();
    final keyString = base64.encode(keyBytes);
    return await encryptMessage(recipientId, keyString);
  }

  Future<void> decryptAndStoreGroupKey(
    String conversationId,
    String encryptedKey,
    String senderId,
  ) async {
    try {
      // Use the 1-on-1 decryption method to decrypt the key itself
      final decryptedKeyString = await decrypt1on1Message(
        senderId,
        encryptedKey,
      );
      if (decryptedKeyString != null &&
          !decryptedKeyString.startsWith('[Error')) {
        final keyStorageIdentifier = 'group_key_$conversationId';
        await _secureStorage.write(
          key: keyStorageIdentifier,
          value: decryptedKeyString,
        );
        print(
          "✅ Successfully decrypted and stored group key for $conversationId",
        );
      } else {
        print("❌ Failed to decrypt the received group key.");
      }
    } catch (e) {
      print("❌ Error processing received group key: $e");
    }
  }
}
