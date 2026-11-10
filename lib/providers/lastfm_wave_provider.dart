import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mornye/services/lastfm_wave_service.dart';
import 'package:mornye/services/secure_storage_options.dart';

const lastfmWaveUsernameKey = 'lastfm_wave_username';
const lastfmWaveApiKeyKey = 'lastfm_wave_api_key';
const lastfmWaveCacheKey = 'lastfm_wave_cache_v1';
const lastfmWaveSecureStorage = FlutterSecureStorage(
  aOptions: secureStorageAndroidOptions,
  mOptions: secureStorageMacOsOptions,
);

class LastfmWaveConfiguration {
  const LastfmWaveConfiguration({
    this.username = '',
    this.apiKey = '',
    this.tracks = const [],
  });
  final String username;
  final String apiKey;
  final List<LastfmWaveTrack> tracks;
}

/// Home's persistence boundary. Tests can supply a profile without starting
/// platform I/O or sharing preferences futures across widget-test zones.
final lastfmWaveConfigurationProvider =
    FutureProvider.autoDispose<LastfmWaveConfiguration>((ref) async {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString(lastfmWaveUsernameKey) ?? '';
      // An unconfigured installation never needs to access the keychain.
      if (username.isEmpty) return const LastfmWaveConfiguration();
      final apiKey =
          await lastfmWaveSecureStorage.read(key: lastfmWaveApiKeyKey) ?? '';
      var tracks = <LastfmWaveTrack>[];
      final raw = prefs.getString(lastfmWaveCacheKey);
      if (raw != null) {
        try {
          final cached = jsonDecode(raw) as Map<String, dynamic>;
          final created = DateTime.parse(cached['created'] as String);
          final age = DateTime.now().difference(created);
          if (cached['username'] == username &&
              age >= Duration.zero &&
              age < const Duration(hours: 6)) {
            tracks = (cached['tracks'] as List)
                .map(
                  (v) => LastfmWaveTrack.fromJson(
                    Map<String, dynamic>.from(v as Map),
                  ),
                )
                .toList();
          }
        } on Object {
          // Corrupt/stale cached metadata can always be fetched again.
        }
      }
      return LastfmWaveConfiguration(
        username: username,
        apiKey: apiKey,
        tracks: tracks,
      );
    });
