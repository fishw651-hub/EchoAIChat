import 'package:aichat/services/encryption_service.dart';
import 'package:aichat/services/secure_session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureStorage implements SecureStorageBackend {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureSessionStore', () {
    test(
      'migrates legacy XOR session once and removes plaintext credentials',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          SecureSessionStore.legacyJwtKey: EncryptionService.encrypt(
            'jwt-value',
          ),
          SecureSessionStore.legacyRefreshKey: EncryptionService.encrypt(
            'refresh-value',
          ),
          SecureSessionStore.legacyApiKey: EncryptionService.encrypt('api-key'),
          SecureSessionStore.legacyApiKeyId: EncryptionService.encrypt(
            'api-key-id',
          ),
          SecureSessionStore.legacyLoginUsernameKey: EncryptionService.encrypt(
            'alice',
          ),
          SecureSessionStore.legacyLoginPassword: EncryptionService.encrypt(
            'password',
          ),
        });
        final preferences = await SharedPreferences.getInstance();
        final storage = _FakeSecureStorage();
        final store = SecureSessionStore(storage: storage);

        final session = await store.loadAndMigrate(preferences);

        expect(session?.jwtToken, 'jwt-value');
        expect(session?.refreshToken, 'refresh-value');
        expect(session?.apiKey, 'api-key');
        expect(session?.apiKeyId, 'api-key-id');
        expect(
          storage.values,
          containsPair(SecureSessionStore.jwtKey, 'jwt-value'),
        );
        expect(
          preferences.containsKey(SecureSessionStore.legacyJwtKey),
          isFalse,
        );
        expect(
          preferences.containsKey(SecureSessionStore.legacyLoginUsernameKey),
          isFalse,
        );
        expect(
          preferences.containsKey(SecureSessionStore.legacyLoginPassword),
          isFalse,
        );
      },
    );

    test(
      'uses an existing secure session without restoring legacy data',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          SecureSessionStore.legacyJwtKey: EncryptionService.encrypt('old-jwt'),
          SecureSessionStore.legacyLoginPassword: EncryptionService.encrypt(
            'old-password',
          ),
        });
        final preferences = await SharedPreferences.getInstance();
        final storage = _FakeSecureStorage()
          ..values[SecureSessionStore.jwtKey] = 'secure-jwt';
        final store = SecureSessionStore(storage: storage);

        final session = await store.loadAndMigrate(preferences);

        expect(session?.jwtToken, 'secure-jwt');
        expect(
          preferences.containsKey(SecureSessionStore.legacyJwtKey),
          isFalse,
        );
        expect(
          preferences.containsKey(SecureSessionStore.legacyLoginPassword),
          isFalse,
        );
      },
    );

    test('clears every secure credential', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = _FakeSecureStorage();
      final store = SecureSessionStore(storage: storage);
      await store.save(
        const SecureSession(
          userId: 42,
          jwtToken: 'jwt',
          refreshToken: 'refresh',
          apiKey: 'api-key',
          apiKeyId: 'api-key-id',
        ),
      );

      expect((await store.read())?.userId, 42);

      await store.clear();

      expect(storage.values, isEmpty);
    });

    test(
      'stores credentials securely and clears them with the session',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final storage = _FakeSecureStorage();
        final store = SecureSessionStore(storage: storage);

        await store.save(
          const SecureSession(username: 'alice', password: 'secret'),
        );

        final session = await store.read();
        expect(session?.username, 'alice');
        expect(session?.password, 'secret');
        expect(
          storage.values,
          isNot(containsPair('auth_login_username', 'alice')),
        );
        expect(
          storage.values,
          isNot(containsPair('auth_login_password', 'secret')),
        );

        await store.clear();

        expect(storage.values, isEmpty);
      },
    );
  });
}
