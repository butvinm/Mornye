import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/models/settings.dart';
import 'package:mornye/models/track.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/providers/extension_provider.dart';
import 'package:mornye/providers/playback_provider.dart';
import 'package:mornye/providers/lastfm_wave_provider.dart';
import 'package:mornye/services/lastfm_wave_resolver.dart';
import 'package:mornye/services/lastfm_wave_service.dart';
import 'package:mornye/widgets/lastfm_wave_card.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() =>
      const AppSettings(playerMode: 'internal', searchProvider: 'deezer');
}

class _Extensions extends ExtensionNotifier {
  @override
  ExtensionState build() => const ExtensionState(
    extensions: [
      Extension(
        id: 'deezer',
        name: 'deezer',
        displayName: 'Deezer',
        version: '1',
        description: '',
        enabled: true,
        status: 'loaded',
        searchBehavior: SearchBehavior(enabled: true),
      ),
    ],
  );
}

class _Playback extends PlaybackController {
  final batches = <List<Track>>[];
  @override
  Future<void> playTrackList(
    List<Track> tracks, {
    int startIndex = 0,
    String origin = 'collection',
  }) async {
    batches.add(tracks);
  }
}

const recommendations = [
  LastfmWaveTrack(title: 'Duality', artist: 'Slipknot'),
  LastfmWaveTrack(title: 'Система', artist: 'Егор Летов'),
  LastfmWaveTrack(title: 'Freak on a Leash', artist: 'Korn'),
];
Track matched(LastfmWaveTrack r) => Track(
  id: 'deezer:${r.title}',
  source: 'deezer',
  name: r.title,
  artistName: r.artist,
  albumName: '',
  duration: 180,
);
void main() {
  Future<ProviderContainer> show(
    WidgetTester tester,
    _Playback playback,
    WaveTrackSearch search,
  ) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        extensionProvider.overrideWith(_Extensions.new),
        playbackProvider.overrideWith(() => playback),
        lastfmWaveConfigurationProvider.overrideWith(
          (ref) async => const LastfmWaveConfiguration(
            username: 'listener',
            apiKey: 'test',
            tracks: recommendations,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: LastfmWaveCard(search: search)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('unmatched selected row never starts matching following song', (
    tester,
  ) async {
    final playback = _Playback();
    final requests = <String>[];
    await show(tester, playback, (r) async {
      requests.add(r.title);
      return r.title == 'Duality' ? [] : [matched(r)];
    });
    await tester.tap(find.text('Duality'));
    await tester.pumpAndSettle();
    expect(requests, ['Duality']);
    expect(playback.batches, isEmpty);
    expect(find.textContaining('Slipknot — Duality'), findsOneWidget);
    await tester.tap(find.text('Система'));
    await tester.pumpAndSettle();
    expect(playback.batches.single.single.id, 'deezer:Система');
    expect(playback.batches.single.single.artistName, 'Егор Летов');
  });
  testWidgets('batch Play can still skip unavailable recommendations', (
    tester,
  ) async {
    final playback = _Playback();
    await show(
      tester,
      playback,
      (r) async => r.title == 'Duality' ? [] : [matched(r)],
    );
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(playback.batches.single.map((t) => t.name), [
      'Система',
      'Freak on a Leash',
    ]);
  });
  testWidgets('configuration replacement invalidates pending row search', (
    tester,
  ) async {
    final playback = _Playback();
    final pending = Completer<List<Track>>();
    final container = await show(tester, playback, (_) => pending.future);
    await tester.tap(find.text('Duality'));
    await tester.pump();
    container.invalidate(lastfmWaveConfigurationProvider);
    await tester.pump();
    await tester.pump();
    pending.complete([matched(recommendations.first)]);
    await tester.pumpAndSettle();
    expect(playback.batches, isEmpty);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
