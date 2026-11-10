import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mornye/providers/lastfm_wave_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () =>
        FlutterSecureStorage.setMockInitialValues({lastfmWaveApiKeyKey: 'key'}),
  );
  for (final invalidation in ['expired', 'different profile', 'malformed']) {
    test(
      'ignores $invalidation cache without losing saved configuration',
      () async {
        SharedPreferences.setMockInitialValues({
          lastfmWaveUsernameKey: 'listener',
          lastfmWaveCacheKey: invalidation == 'malformed'
              ? '{'
              : jsonEncode({
                  'username': invalidation == 'different profile'
                      ? 'someone_else'
                      : 'listener',
                  'created': DateTime.now()
                      .subtract(
                        Duration(hours: invalidation == 'expired' ? 7 : 1),
                      )
                      .toIso8601String(),
                  'tracks': [
                    {'title': 'Song', 'artist': 'Artist'},
                  ],
                }),
        });
        final container = ProviderContainer.test();
        final configuration = await container.read(
          lastfmWaveConfigurationProvider.future,
        );
        expect(configuration.username, 'listener');
        expect(configuration.apiKey, 'key');
        expect(configuration.tracks, isEmpty);
      },
    );
  }
}
