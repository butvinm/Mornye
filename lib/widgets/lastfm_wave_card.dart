import 'package:mornye/services/playback_diagnostics.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mornye/utils/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mornye/models/track.dart';
import 'package:mornye/controllers/home_search_logic.dart';
import 'package:mornye/controllers/extension_auth_launcher.dart';
import 'package:mornye/providers/extension_provider.dart';
import 'package:mornye/providers/playback_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/services/lastfm_wave_service.dart';
import 'package:mornye/services/lastfm_wave_resolver.dart';
import 'package:mornye/services/platform_bridge.dart';
import 'package:mornye/providers/lastfm_wave_provider.dart';

/// A small, explicit Last.fm radio batch. Audio uses the app's normal provider
/// and download/playback queue; Last.fm URLs are never treated as audio URLs.
class LastfmWaveCard extends ConsumerStatefulWidget {
  const LastfmWaveCard({super.key, this.service, this.search});

  /// Optional client for deterministic UI tests; disposed with the card.
  final LastfmWaveService? service;

  /// Optional metadata search for deterministic selection/lifecycle tests.
  final WaveTrackSearch? search;

  @override
  ConsumerState<LastfmWaveCard> createState() => _LastfmWaveCardState();
}

class _LastfmWaveCardState extends ConsumerState<LastfmWaveCard> {
  LastfmWaveService? _service;
  String _username = '';
  String _apiKey = '';
  List<LastfmWaveTrack> _tracks = [];
  bool _loading = false;
  bool _playing = false;
  bool _configurationPending = true;
  bool _configurationError = false;
  String? _message;
  LastfmWaveException? _requestError;
  bool _hasSuccessfulLoad = false;
  int _generation = 0;
  int _playGeneration = 0;

  String t(String ru, String en) =>
      Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

  @override
  void initState() {
    super.initState();
    ref.listenManual(lastfmWaveConfigurationProvider, (previous, next) {
      next.whenData((configuration) {
        if (!mounted) return;
        setState(() {
          _generation++;
          _configurationPending = false;
          _configurationError = false;
          _username = configuration.username;
          _apiKey = configuration.apiKey;
          _tracks = configuration.tracks;
          _hasSuccessfulLoad = _tracks.isNotEmpty;
          _requestError = null;
          _loading = false;
        });
        if (_username.isNotEmpty && _apiKey.isNotEmpty && _tracks.isEmpty) {
          _refresh();
        }
      });
      if (next.hasError && mounted) {
        setState(() {
          _loading = false;
          _configurationPending = false;
          _configurationError = true;
        });
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _generation++;
    _service?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _message = null;
      _requestError = null;
    });
    try {
      final tracks = await (_service ??= widget.service ?? LastfmWaveService())
          .recommend(username: _username, apiKey: _apiKey);
      if (!mounted || generation != _generation) return;
      setState(() {
        _tracks = tracks;
        _hasSuccessfulLoad = true;
      });
      // Cache storage failure must not turn a successful API response into an error.
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted || generation != _generation) return;
        await prefs.setString(
          lastfmWaveCacheKey,
          jsonEncode({
            'username': _username,
            'created': DateTime.now().toIso8601String(),
            'tracks': tracks.map((track) => track.toJson()).toList(),
          }),
        );
      } on Object {
        AppLogger('LastfmWave').w('Last.fm cache_write_failed');
      }
    } on LastfmWaveException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _requestError = error);
      }
    } on Object {
      const error = LastfmWaveException(
        'Could not load your wave. Retry; diagnostics are available below.',
        kind: LastfmWaveErrorKind.client,
      );
      AppLogger('LastfmWave').e(error.diagnostic);
      if (mounted && generation == _generation) {
        setState(() => _requestError = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _configure() async {
    if (_configurationPending) {
      try {
        await ref.read(lastfmWaveConfigurationProvider.future);
      } on Object {
        // Still allow replacing credentials when persistence failed to load.
      }
      if (!mounted) return;
    }
    final username = TextEditingController(text: _username);
    final key = TextEditingController(text: _apiKey);
    final form = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('Настроить Last.fm', 'Set up Last.fm')),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t(
                    'Используется история прослушиваний публичного профиля. Пароль не нужен.',
                    'Uses your public listening history. No password is needed.',
                  ),
                ),
                TextFormField(
                  controller: username,
                  decoration: InputDecoration(
                    labelText: t('Имя пользователя', 'Username'),
                  ),
                  autocorrect: false,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? t('Укажите профиль', 'Enter a username')
                      : null,
                ),
                TextFormField(
                  controller: key,
                  decoration: const InputDecoration(
                    labelText: 'Last.fm API key',
                  ),
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: (v) =>
                      v == null ||
                          !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(v.trim())
                      ? t(
                          'Укажите API key (32 символа)',
                          'Enter a 32-character API key',
                        )
                      : null,
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('https://www.last.fm/api/account/create'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(t('Получить API key', 'Get an API key')),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: Text(t('Сохранить', 'Save')),
          ),
        ],
      ),
    );
    final nextUsername = username.text.trim();
    final nextKey = key.text.trim();
    // The dialog route may still animate with these controllers after pop.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    username.dispose();
    key.dispose();
    if (result != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await lastfmWaveSecureStorage.write(
        key: lastfmWaveApiKeyKey,
        value: nextKey,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastfmWaveUsernameKey, nextUsername);
      await prefs.remove(lastfmWaveCacheKey);
      if (!mounted) return;
      setState(() {
        _configurationError = false;
        _username = nextUsername;
        _apiKey = nextKey;
        _tracks = [];
      });
      await _refresh();
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = t(
            'Не удалось сохранить настройки.',
            'Could not save settings.',
          );
        });
      }
    }
  }

  Future<void> _play({LastfmWaveTrack? selectedTrack}) async {
    if (_playing || _loading) return;
    final generation = _generation;
    final playGeneration = ++_playGeneration;
    bool current() =>
        mounted &&
        generation == _generation &&
        playGeneration == _playGeneration;
    // A row means that exact recording. Only batch Play may skip misses.
    final candidates = List<LastfmWaveTrack>.of(
      selectedTrack == null ? _tracks.take(5) : [selectedTrack],
    );
    final attempt = PlaybackDiagnostics.begin('wave');
    if (selectedTrack != null) {
      PlaybackDiagnostics.event(
        'wave_selected',
        attempt: attempt,
        fields: {'title': selectedTrack.title, 'artist': selectedTrack.artist},
      );
    }
    setState(() {
      _playing = true;
      _message = null;
    });
    try {
      final settings = ref.read(settingsProvider);
      if (settings.playerMode != 'internal') {
        throw StateError(
          t(
            'Включите встроенный плеер в настройках воспроизведения.',
            'Enable the internal player in playback settings.',
          ),
        );
      }
      final extensions = ref.read(extensionProvider).extensions;
      final selected = HomeSearchProviderPolicy.resolveProvider(
        settings.searchProvider,
        extensions,
      );
      final source = extensions.where((e) => e.id == selected).firstOrNull;
      if (source == null) {
        throw StateError(
          t(
            'Добавьте и включите источник поиска в расширениях.',
            'Add and enable a search provider in Extensions.',
          ),
        );
      }
      // Resolve a bounded batch so pressing Play never downloads the entire
      // recommendation list. Unmatched versions are skipped, never substituted.
      var verificationAttempted = false;
      var verificationDenied = false;
      final resolved = await resolveWaveBatch(candidates, (
        recommendation,
      ) async {
        if (!current() || verificationDenied) return [];
        if (widget.search != null) return widget.search!(recommendation);
        Future<List<Map<String, dynamic>>> search(String query) =>
            PlatformBridge.customSearchWithExtension(
              source.id,
              query,
              options: {'filter': 'track'},
            ).timeout(const Duration(seconds: 20));
        return searchWaveCandidates(
          recommendation,
          (query) async {
            if (!current()) return [];
            List<Map<String, dynamic>> results;
            try {
              results = await search(query);
            } catch (error) {
              if (!current() ||
                  !isExtensionVerificationRequired(error) ||
                  verificationAttempted) {
                rethrow;
              }
              verificationAttempted = true;
              final verified = await openVerificationAndAwaitGrant(
                source.id,
                browserMode: settings.extensionVerificationBrowserMode,
              );
              if (!verified) {
                verificationDenied = true;
                rethrow;
              }
              if (!current()) return [];
              results = await search(query);
            }
            return results
                .map((row) => Track.fromBackendMap(row, source: source.id))
                .toList();
          },
          onResult: (phase, count, matched) {
            PlaybackDiagnostics.event(
              'wave_retrieval',
              attempt: attempt,
              fields: {
                'title': recommendation.title,
                'artist': recommendation.artist,
                'source': source.id,
                'count': count,
                'result':
                    '$phase:${matched
                        ? 'matched'
                        : count == 0
                        ? 'empty'
                        : 'candidates_rejected'}',
              },
            );
          },
        );
      });
      final batch = resolved.tracks;
      if (!current()) return;
      for (final requested in candidates) {
        final match = matchWaveTrack(requested, batch);
        PlaybackDiagnostics.event(
          'wave_match',
          attempt: attempt,
          fields: {
            'title': requested.title,
            'artist': requested.artist,
            'result': match == null
                ? (resolved.failures > 0 ? 'lookup_failed' : 'no_exact_match')
                : 'matched',
            if (match != null) 'trackId': match.id,
            if (match != null) 'source': match.source ?? '',
          },
        );
      }
      if (selectedTrack != null && batch.isEmpty) {
        throw StateError(
          t(
            'Не удалось найти выбранный трек: ${selectedTrack.artist} — ${selectedTrack.title}. Другой трек не запущен.',
            'Could not find the selected track: ${selectedTrack.artist} — ${selectedTrack.title}. Playback was not changed.',
          ),
        );
      }
      if (batch.isEmpty && resolved.failures > 0) {
        throw StateError(
          t(
            'Источник музыки не ответил или требует верификацию. Проверьте его и повторите.',
            'The music provider failed or requires verification. Check it and retry.',
          ),
        );
      }
      if (batch.isEmpty) {
        throw StateError(
          t(
            'Источник не нашёл подходящие версии треков. Попробуйте другой источник поиска.',
            'No matching recordings found. Try another search provider.',
          ),
        );
      }
      if (!current()) return;
      PlaybackDiagnostics.event(
        'wave_start',
        attempt: attempt,
        fields: {
          'trackId': batch.first.id,
          'title': batch.first.name,
          'artist': batch.first.artistName,
          'count': batch.length,
        },
      );
      await ref
          .read(playbackProvider.notifier)
          .playTrackList(batch, origin: 'wave');
      if (current()) {
        setState(
          () => _message = t(
            'В очередь добавлено: ${batch.length}.${resolved.failures > 0 ? ' Часть запросов к источнику не удалась.' : ''}',
            'Queued ${batch.length} tracks.${resolved.failures > 0 ? ' Some provider lookups failed.' : ''}',
          ),
        );
      }
    } on StateError catch (error) {
      if (current()) setState(() => _message = error.message.toString());
    } on Object {
      if (current()) {
        setState(
          () => _message = t(
            'Не удалось запустить волну. Проверьте источник музыки, загрузки и его верификацию.',
            'Could not start your wave. Check your music provider, downloads and its verification.',
          ),
        );
      }
    } finally {
      if (mounted && playGeneration == _playGeneration) {
        setState(() => _playing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = _username.isNotEmpty && _apiKey.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.waves_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t('Моя волна', 'My wave'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: t('Настроить Last.fm', 'Set up Last.fm'),
                  onPressed: _loading || _playing ? null : _configure,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            Text(
              configured
                  ? t(
                      'По вашему профилю Last.fm · $_username',
                      'From your Last.fm profile · $_username',
                    )
                  : t(
                      'Музыка по вашему вкусу из Last.fm',
                      'Music inspired by your Last.fm listening',
                    ),
            ),
            const SizedBox(height: 12),
            if ((_loading && configured) || _playing) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                _playing
                    ? t(
                        'Ищем музыку в вашем источнике…',
                        'Finding music in your provider…',
                      )
                    : t('Собираем волну…', 'Building your wave…'),
              ),
            ],
            if (_configurationError)
              Text(
                t(
                  'Не удалось прочитать настройки Last.fm.',
                  'Could not read Last.fm settings.',
                ),
              ),
            if (_requestError != null) ...[
              Text(
                _requestError!.localizedMessage(
                  russian: Localizations.localeOf(context).languageCode == 'ru',
                ),
              ),
              SelectableText(_requestError!.diagnostic),
              TextButton.icon(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: _requestError!.diagnostic),
                ),
                icon: const Icon(Icons.copy),
                label: Text(t('Копировать диагностику', 'Copy diagnostics')),
              ),
            ],
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_message!),
              ),
            if (!configured)
              FilledButton(
                onPressed: _loading ? null : _configure,
                child: Text(t('Подключить Last.fm', 'Connect Last.fm')),
              ),
            if (configured && !_loading) ...[
              if (_tracks.isEmpty &&
                  _hasSuccessfulLoad &&
                  _requestError == null)
                Text(
                  t(
                    'В профиле Last.fm нет истории прослушиваний. Нужны скробблы в Last.fm; локальная библиотека Mornye не создаёт их автоматически.',
                    'Your Last.fm profile has no listening history. Scrobble tracks to Last.fm first; your local Mornye library does not add them automatically.',
                  ),
                ),
              if (_tracks.isNotEmpty) ...[
                Text(
                  t(
                    'Ищем до 5 треков из подборки и воспроизводим через загрузки Mornye.',
                    'Plays up to 5 matching tracks using Mornye downloads.',
                  ),
                ),
                for (final track in _tracks.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.play_arrow_rounded),
                    onTap: _playing || _loading
                        ? null
                        : () => _play(selectedTrack: track),
                  ),
              ],
              Wrap(
                spacing: 8,
                children: [
                  if (_tracks.isNotEmpty)
                    FilledButton.icon(
                      onPressed: _playing || _loading ? null : () => _play(),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(t('Слушать', 'Play')),
                    ),
                  if (_tracks.length > 5)
                    TextButton.icon(
                      onPressed: _playing
                          ? null
                          : () => setState(() {
                              _tracks = [
                                ..._tracks.skip(5),
                                ..._tracks.take(5),
                              ];
                            }),
                      icon: const Icon(Icons.skip_next),
                      label: Text(t('Другие треки', 'More tracks')),
                    ),
                  TextButton.icon(
                    onPressed: _playing ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(t('Обновить', 'Refresh')),
                  ),
                ],
              ),
              if (!Platform.isAndroid)
                Text(
                  t(
                    'На этой платформе воспроизводятся уже загруженные треки.',
                    'On this platform, playback requires downloaded tracks.',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
