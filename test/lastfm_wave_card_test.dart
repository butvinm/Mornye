import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mornye/services/lastfm_wave_service.dart';
import 'package:mornye/providers/lastfm_wave_provider.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mornye/widgets/lastfm_wave_card.dart';

void main() {
  testWidgets('API error is not empty history and refresh recovers', (
    tester,
  ) async {
    var reject = true;
    final service = LastfmWaveService(
      client: MockClient(
        (_) async => reject
            ? http.Response('{"error":10,"message":"secret"}', 403)
            : http.Response('{"toptracks":{"track":[]}}', 200),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lastfmWaveConfigurationProvider.overrideWith(
            (ref) async => const LastfmWaveConfiguration(
              username: 'listener',
              apiKey: 'secret',
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LastfmWaveCard(service: service),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy diagnostics'), findsOneWidget);
    expect(find.textContaining('http=403 api=10'), findsOneWidget);
    expect(find.textContaining('has no listening history'), findsNothing);
    expect(find.text('secret'), findsNothing);
    reject = false;
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Copy diagnostics'), findsNothing);
    expect(find.textContaining('has no listening history'), findsOneWidget);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  Future<void> showCard(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: LastfmWaveCard())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unconfigured Home offers setup without requesting audio', (
    tester,
  ) async {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var secureReads = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'read') secureReads++;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await showCard(tester);
    expect(secureReads, 0);
    // An unconfigured Home must not wait on the keychain or leave a loader.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('My wave'), findsOneWidget);
    expect(find.text('Connect Last.fm'), findsOneWidget);
    await tester.tap(find.text('Connect Last.fm'));
    await tester.pumpAndSettle();
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Last.fm API key'), findsOneWidget);
    expect(find.text('Get an API key'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a username'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'fresh profile cache displays playable recommendations without API key exposure',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'lastfm_wave_api_key': 'a' * 32,
      });
      SharedPreferences.setMockInitialValues({
        'lastfm_wave_username': 'listener',
        'lastfm_wave_cache_v1': jsonEncode({
          'username': 'listener',
          'created': DateTime.now().toIso8601String(),
          'tracks': [
            {'title': 'Get Lucky', 'artist': 'Daft Punk'},
          ],
        }),
      });
      await showCard(tester);
      expect(find.text('Get Lucky'), findsOneWidget);
      expect(find.text('Daft Punk'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('a' * 32), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('More tracks exposes later recommendations without downloading', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'lastfm_wave_api_key': 'a' * 32,
    });
    SharedPreferences.setMockInitialValues({
      'lastfm_wave_username': 'listener',
      'lastfm_wave_cache_v1': jsonEncode({
        'username': 'listener',
        'created': DateTime.now().toIso8601String(),
        'tracks': List.generate(
          12,
          (i) => {'title': 'Song $i', 'artist': 'Artist'},
        ),
      }),
    });
    await showCard(tester);
    expect(find.text('Song 0'), findsOneWidget);
    expect(find.text('Song 5'), findsNothing);
    await tester.ensureVisible(find.text('More tracks'));
    await tester.tap(find.text('More tracks'));
    await tester.pumpAndSettle();
    expect(find.text('Song 0'), findsNothing);
    expect(find.text('Song 5'), findsOneWidget);
    await tester.tap(find.text('More tracks'));
    await tester.pumpAndSettle();
    expect(find.text('Song 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final fail in [false, true]) {
    testWidgets(
      'Mornye Home remains usable after async configuration (error: $fail)',
      (tester) async {
        final configuration = Completer<LastfmWaveConfiguration>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              lastfmWaveConfigurationProvider.overrideWith(
                (ref) => configuration.future,
              ),
            ],
            child: MaterialApp(
              theme: MornyeTheme.build(Brightness.dark),
              home: const Scaffold(body: LastfmWaveCard()),
            ),
          ),
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        if (fail) {
          configuration.completeError(StateError('keychain unavailable'));
        } else {
          configuration.complete(const LastfmWaveConfiguration());
        }
        await tester.pumpAndSettle();
        expect(find.text('Connect Last.fm'), findsOneWidget);
        if (fail) {
          expect(find.text('Could not read Last.fm settings.'), findsOneWidget);
        }
        await tester.tap(find.text('Connect Last.fm'));
        await tester.pumpAndSettle();
        expect(find.text('Username'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Mornye refresh can disable and re-enable controls after a request',
    (tester) async {
      final response = Completer<http.Response>();
      final service = LastfmWaveService(
        client: MockClient((request) => response.future),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lastfmWaveConfigurationProvider.overrideWith(
              (ref) async => const LastfmWaveConfiguration(
                username: 'listener',
                apiKey: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                tracks: [LastfmWaveTrack(title: 'Song', artist: 'Artist')],
              ),
            ),
          ],
          child: MaterialApp(
            theme: MornyeTheme.build(Brightness.dark),
            home: Scaffold(
              body: SingleChildScrollView(
                child: LastfmWaveCard(service: service),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      response.complete(http.Response('{"toptracks":{"track":[]}}', 200));
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.text(
          'Your Last.fm profile has no listening history. Scrobble tracks to Last.fm first; your local Mornye library does not add them automatically.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Set up Last.fm'));
      await tester.pumpAndSettle();
      expect(find.text('Username'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
