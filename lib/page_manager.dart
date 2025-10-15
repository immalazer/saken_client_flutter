import 'dart:convert';
import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart' as status;
import 'model/song_model.dart';

class PageManager {
  int currentIndex = 0;
  final _textFieldController = TextEditingController();
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

  String host = 'localhost';
  String apiPort = "8000";
  String websocketPort = "8080";
  String webSocketKey = "h3rixwse35kzcnrmdptw";
  String apiUrl = "";
  String webSocketUrl = "";

  late AudioPlayer _audioPlayer;
  PageManager() {
    _init();
  }

  void _init() async {
    apiUrl = "http://$host:$apiPort/api";
    webSocketUrl = "ws://$host:$websocketPort/app/$webSocketKey";

    JustAudioMediaKit.protocolWhitelist = ["http", "https", "file"];
    JustAudioMediaKit.title = 'Saken';
    JustAudioMediaKit.ensureInitialized();

    subscribe();
    refresh();

    _audioPlayer = AudioPlayer();

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

  void setServerHost(String url) {
    host = url;
    apiUrl = "http://$host:$apiPort/api";
    webSocketUrl = "ws://$host:$websocketPort/app/$webSocketKey";

    // Re-initialize our connection
    subscribe();
    refresh();
  }

  void subscribe() async {
    final channel = status.WebSocketChannel.connect(Uri.parse(webSocketUrl));

    try {
      await channel.ready;

      final subscription = {
        "event": "pusher:subscribe",
        "data": {"channel": "songs-updates"},
      };
      channel.sink.add(jsonEncode(subscription));
      channel.stream.listen(
        cancelOnError: true,
        (message) {
          final data = jsonDecode(message);

          if (data['channel'] == 'songs-updates') {
            final eventData = jsonDecode(data['data']);
            switch (eventData['message']) {
              case 'update':
                // Generic update message. Refresh immediately.
                refresh();
                break;
              case 'delete':
                songListNotifier.value.songList.removeWhere(
                  (item) => item.filename == eventData['which'],
                );
                // This is so dumb, but whatever.
                songListNotifier.value = SongListState(
                  songList: songListNotifier.value.songList,
                );
                break;
            }
          }

          // Listen on ping and return a pong
          if (message.toString().contains('ping')) {
            channel.sink.add(json.encode({"event": "pusher:pong"}));
          }
        },
        onDone: () {
          print('Connection closed.');
        },
        onError: (error) {
          print(error);
        },
      );
    } catch (error) {
      // Something really bad happened.
    }
  }

  void queue(String path, int index) async {
    // Save the current index for use with fast forward and prev.
    currentIndex = index;
    try {
      http.get(Uri.parse('$apiUrl/play/$path')).then((value) async {
        if (buttonNotifier.value == ButtonState.playing) {
          pause();
        }
        var file = await DefaultCacheManager().getSingleFile(
          jsonDecode(value.body)['message'],
        );
        songMetadataNotifier.value = MetadataNotifier(
          album: songListNotifier.value.songList[index].album,
          artist: songListNotifier.value.songList[index].artist,
          title: songListNotifier.value.songList[index].title,
        );
        _audioPlayer.setFilePath(file.path);
        play();
      });
    } catch (e) {
      // Something really terrible has happened, and we shouldn't ignore it.
    }
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

  void refresh() {
    futureSongs = fetchSongs().then((value) {
      songListNotifier.value = SongListState(songList: value);
      return songListNotifier.value.songList;
    });
  }

  void deleteSong(int index) async {
    try {
      var filename = songListNotifier.value.songList[index].filename;
      var postUri = Uri.parse("$apiUrl/songs/$filename");
      var request = http.MultipartRequest("DELETE", postUri);
      request.send();
    } catch (e) {
      // Something really terrible has happened, and we shouldn't ignore it.
    }
  }

  Future<void> showSongOptionDialog(BuildContext context, int index) async {
    switch (await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          title: Text(songListNotifier.value.songList[index].title),
          children: <Widget>[
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 'delete');
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    )) {
      case 'delete':
        deleteSong(index);
        break;
      case null:
        // dialog dismissed
        break;
    }
  }

  Future<String?> showTextInputDialog(
    BuildContext context,
    String title,
    String hint,
  ) async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: _textFieldController,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: <Widget>[
            ElevatedButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text('OK'),
              onPressed: () =>
                  Navigator.pop(context, _textFieldController.text),
            ),
          ],
        );
      },
    );
  }

  Future<List<Song>> fetchSongs() async {
    try {
      final response = await http.get(Uri.parse("$apiUrl/songs"));

      if (response.statusCode == 200) {
        List<dynamic> json = jsonDecode(response.body);
        return json.map((data) => Song.fromJson(data)).toList();
      } else {
        throw Exception('Failed to load song');
      }
    } catch (e) {
      // Something really terrible has happened, and we shouldn't ignore it.
    }
    return List.empty();
  }

  Future<String?> getAlbumArt(int index) async {
    try {
      final filename = songListNotifier.value.songList[index].filename;
      final response = await http.get(Uri.parse("$apiUrl/art/$filename"));

      if (response.statusCode == 200) {
        return jsonDecode(response.body)['message'];
      } else {
        return null;
      }
    } catch (e) {
      // Something really terrible has happened, and we shouldn't ignore it.
    }
    return null;
  }

  void uploadSong() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);
      try {
        var metadata = readMetadata(file, getImage: true);

        var postUri = Uri.parse("$apiUrl/songs");
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

        if (metadata.pictures.isNotEmpty) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'art',
              metadata.pictures[0].bytes,
              filename: filename,
            ),
          );
        }

        request.send();
      } catch (e) {
        // Something really terrible has happened, and we shouldn't ignore it.
      }
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
