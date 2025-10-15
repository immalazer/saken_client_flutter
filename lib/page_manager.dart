import 'dart:convert';
import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http_parser/http_parser.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'model/song_model.dart';

class PageManager {
  int currentIndex = 0;
  late Future<List<Song>> futureSongs;

  final songListNotifier = ValueNotifier<SongListState>(
    SongListState(songList: List.empty()),
  );
  final songMetadataNotifier = ValueNotifier<MetadataNotifier>(
    MetadataNotifier(album: "No album", title: "No track"),
  );
  final progressNotifier = ValueNotifier<ProgressBarState>(
    ProgressBarState(
      current: Duration.zero,
      buffered: Duration.zero,
      total: Duration.zero,
    ),
  );
  final buttonNotifier = ValueNotifier<ButtonState>(ButtonState.paused);

  static const apiUrl = 'http://localhost:8000/api/songs/';
  static const url = 'https://freepd.com/music/3%20am%20West%20End.mp3';

  late AudioPlayer _audioPlayer;
  PageManager() {
    _init();
  }

  void _init() async {
    JustAudioMediaKit.protocolWhitelist = [
      "http",
      "https",
      "file", // notice how we allow the file protocol when reading assets!
    ];
    JustAudioMediaKit.title = 'Saken';
    JustAudioMediaKit.ensureInitialized(
      linux: true,
      windows: true,
      android: true,
      iOS: true,
      macOS: true,
    );

    var file = await DefaultCacheManager().getSingleFile(url);

    futureSongs = fetchSongs().then((value) {
      songListNotifier.value = SongListState(songList: value);
      return List.empty();
    });

    _audioPlayer = AudioPlayer();
    await _audioPlayer.setFilePath(file.path);

    _audioPlayer.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;
      if (processingState == ProcessingState.loading ||
          processingState == ProcessingState.buffering) {
        buttonNotifier.value = ButtonState.loading;
      } else if (!isPlaying) {
        buttonNotifier.value = ButtonState.paused;
      } else if (processingState != ProcessingState.completed) {
        buttonNotifier.value = ButtonState.playing;
      } else {
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.pause();
      }
    });

    _audioPlayer.positionStream.listen((position) {
      final oldState = progressNotifier.value;
      progressNotifier.value = ProgressBarState(
        current: position,
        buffered: oldState.buffered,
        total: oldState.total,
      );
    });

    _audioPlayer.bufferedPositionStream.listen((bufferedPosition) {
      final oldState = progressNotifier.value;
      progressNotifier.value = ProgressBarState(
        current: oldState.current,
        buffered: bufferedPosition,
        total: oldState.total,
      );
    });

    _audioPlayer.durationStream.listen((totalDuration) {
      final oldState = progressNotifier.value;
      progressNotifier.value = ProgressBarState(
        current: oldState.current,
        buffered: oldState.buffered,
        total: totalDuration ?? Duration.zero,
      );
    });
  }

  void queue(String path, int index) async {
    // Save the current index for use with fast forward and prev.
    currentIndex = index;

    pause();
    http.get(Uri.parse('http://localhost:8000/api/play/$path')).then((
      value,
    ) async {
      var file = await DefaultCacheManager().getSingleFile(
        jsonDecode(value.body)['message'],
      );
      var metadata = readMetadata(file);
      songMetadataNotifier.value = MetadataNotifier(
        album: metadata.album ?? "No album",
        artist: metadata.artist ?? "Unknown",
        title: metadata.title ?? "No title",
      );
      _audioPlayer.setFilePath(file.path);
      play();
    });
  }

  void play() {
    _audioPlayer.play();
  }

  void pause() {
    _audioPlayer.pause();
  }

  void seek(Duration position) {
    _audioPlayer.seek(position);
  }

  void dispose() {
    _audioPlayer.dispose();
  }

  void rewind() {
    if (currentIndex - 1 < 0) {
      queue(
        songListNotifier.value.songList[currentIndex].filename,
        currentIndex,
      );
    } else {
      queue(
        songListNotifier.value.songList[currentIndex - 1].filename,
        currentIndex - 1,
      );
    }
  }

  void fastForward() {
    if (currentIndex + 1 == songListNotifier.value.songList.length) {
      queue(
        songListNotifier.value.songList[currentIndex].filename,
        currentIndex,
      );
    } else {
      queue(
        songListNotifier.value.songList[currentIndex + 1].filename,
        currentIndex + 1,
      );
    }
  }

  Future<List<Song>> fetchSongs() async {
    final response = await http.get(Uri.parse(apiUrl));

    if (response.statusCode == 200) {
      List<dynamic> json = jsonDecode(response.body);
      return json.map((data) => Song.fromJson(data)).toList();
    } else {
      throw Exception('Failed to load song');
    }
  }

  void uploadSong() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      var metadata = readMetadata(file);

      var postUri = Uri.parse("http://localhost:8000/api/songs");
      var request = http.MultipartRequest("POST", postUri);
      var filename = Uuid().v4().toString();
      request.fields['title'] = metadata.title ?? basename(file.path);
      request.fields['artist'] = metadata.artist ?? "Unknown";
      request.fields['album'] = metadata.album ?? "No album";
      request.fields['duration'] = metadata.duration.toString();
      request.fields['filename'] = filename;
      request.files.add(
        http.MultipartFile(
          'file',
          file.readAsBytes().asStream(),
          file.lengthSync(),
          filename: filename,
        ),
      );

      request.send().then((response) {
        if (response.statusCode == 201) {
          fetchSongs().then((value) {
            songListNotifier.value = SongListState(songList: value);
            return List.empty();
          });
        }
      });
    } else {
      // User canceled the picker
    }
  }
}

class ProgressBarState {
  ProgressBarState({
    required this.current,
    required this.buffered,
    required this.total,
  });
  final Duration current;
  final Duration buffered;
  final Duration total;
}

enum ButtonState { paused, playing, loading }

class SongListState {
  SongListState({required this.songList});
  final List<Song> songList;
}

class MetadataNotifier {
  MetadataNotifier({
    this.album = "No album",
    this.artist = "Unknown",
    this.title = "No track",
  });
  final String? album;
  final String? artist;
  final String? title;
}
