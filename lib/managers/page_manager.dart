import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:http/http.dart' as http;
import 'package:saken/clients/api_client.dart';
import 'package:saken/helper/utils.dart';
import 'package:saken/managers/device_manager.dart';
import 'package:saken/helper/navigation_service.dart';
import 'package:saken/clients/websocket_client.dart';
import '../model/song_model.dart';

class PageManager {
  int currentIndex = 0;

  late Future<List<Song>> futureSongs;
  late DeviceManager deviceManager;
  late ApiClient apiClient;
  late WebSocketClient webSocketClient;

  final songListNotifier = ValueNotifier<SongListState>(
    SongListState(songList: List.empty()),
  );

  final songMetadataNotifier = ValueNotifier<MetadataNotifier>(
    MetadataNotifier(album: "No album", artist: "Unknown", title: "No track"),
  );

  final progressNotifier = ValueNotifier<ProgressBarState>(
    ProgressBarState(
      current: Duration.zero,
      buffered: Duration.zero,
      total: Duration.zero,
    ),
  );

  final buttonNotifier = ValueNotifier<ButtonState>(ButtonState.paused);

  late AudioPlayer _audioPlayer;

  PageManager() {
    _init();
  }

  void _init() async {
    deviceManager = DeviceManager();
    apiClient = ApiClient();
    webSocketClient = WebSocketClient();

    JustAudioMediaKit.protocolWhitelist = ["http", "https", "file"];
    JustAudioMediaKit.title = 'Saken';
    JustAudioMediaKit.ensureInitialized();

    // Fetch relevant device identifier, then register it
    deviceManager.getDeviceIdentifier().then((value) {
      deviceManager.registerDevice(value, apiClient);
    });

    // Start the connection.
    await reconnect();

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

  void queue(String path, int index, {String? origin}) async {
    // Save the current index for use with fast forward and prev.
    currentIndex = index;

    try {
      // We have to ensure that we stop any existing audio source,
      // otherwise there's a chance that the same audio source is
      // played when we queue another. Oddly, this only happens on
      // web and introducing this on mobile & desktop causes regressions
      // on syncing.
      if ((_audioPlayer.playing) && kIsWeb) {
        _audioPlayer.stop();
      }

      _audioPlayer
          .setUrl('${apiClient.apiUrl}/play/$path', preload: false)
          .then((value) async {
            songMetadataNotifier.value = MetadataNotifier(
              album: songListNotifier.value.songList[index].album,
              artist: songListNotifier.value.songList[index].artist,
              title: songListNotifier.value.songList[index].title,
            );

            if (deviceManager.isDeviceSyncing() && origin == null) {
              await queueOnExternalDevice(
                path,
                deviceManager.syncedDevice,
              ).then((_) => play(origin: origin));
            } else {
              play(origin: origin);
            }
          });
    } catch (e) {
      // Something really terrible has happened, and we shouldn't ignore it.
    }
  }

  void play({String? origin}) async {
    if (deviceManager.isDeviceSyncing() && origin == null) {
      deviceManager
          .invokeDeviceCommand('play', deviceManager.syncedDevice, apiClient)
          .then((_) => _audioPlayer.play());
    } else {
      _audioPlayer.play();
    }
  }

  void pause({String? origin}) async {
    if (deviceManager.isDeviceSyncing() && origin == null) {
      await deviceManager
          .invokeDeviceCommand('pause', deviceManager.syncedDevice, apiClient)
          .then((_) => _audioPlayer.pause());
    } else {
      _audioPlayer.pause();
    }
  }

  void seek(Duration position, {String? origin}) async {
    if (deviceManager.isDeviceSyncing() && origin == null) {
      deviceManager
          .invokeDeviceCommand(
            'seek',
            deviceManager.syncedDevice,
            apiClient,
            data: position,
          )
          .then((_) => _audioPlayer.seek(position));
    } else {
      _audioPlayer.seek(position);
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }

  void skip(int direction) {
    int newIndex = currentIndex;

    if (direction == 1) {
      // WEIRD. Don't ask about this.
      newIndex = currentIndex + 1 > songListNotifier.value.songList.length - 1
          ? currentIndex
          : currentIndex + 1;
    } else if (direction == 0) {
      newIndex = currentIndex - 1 < 0 ? currentIndex : currentIndex - 1;
    }

    queue(songListNotifier.value.songList[newIndex].filename, newIndex);
  }

  void refresh() {
    futureSongs = apiClient.fetchSongs().then((value) {
      songListNotifier.value = SongListState(songList: value);
      return songListNotifier.value.songList;
    });
  }

  Future<void> queueOnExternalDevice(String filename, String targetId) async {
    try {
      var postUri = Uri.parse("${apiClient.apiUrl}/devices/$targetId");
      var request = http.MultipartRequest("POST", postUri);

      request.fields['reason'] = "queue";
      request.fields['origin'] = deviceManager.getUniqueId();
      request.fields['key'] = targetId;
      request.fields['filename'] = filename;

      await request.send();
    } catch (e) {
      // More fire, yay.
    }
  }

  Future<String> showDeviceSelectionDialog(
    BuildContext context,
    bool syncMenu,
  ) async {
    try {
      final response = await http.get(Uri.parse("${apiClient.apiUrl}/devices"));
      if (response.statusCode == 200 && context.mounted) {
        List<Widget> devices = <Widget>[];
        List<dynamic> json = jsonDecode(response.body);
        String choice = "";

        for (var value in json) {
          if (value['key'] == deviceManager.getUniqueId()) continue;

          IconData deviceIcon = Icons.web_rounded;

          switch (value['device_type']) {
            case 'web':
              deviceIcon = Icons.public_rounded;
              break;
            case "pc":
              deviceIcon = Icons.computer_rounded;
              break;
            case "mobile":
              deviceIcon = Icons.phone_android_rounded;
              break;
          }
          devices.add(
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, value['key']);
              },
              child: Row(
                children: <Widget>[
                  Icon(deviceIcon),
                  SizedBox(width: 12),
                  Text(value['nickname']),
                ],
              ),
            ),
          );
        }

        if (!deviceManager.isDeviceSyncing() || !syncMenu) {
          await showDialog<String>(
            context: context,
            builder: (BuildContext context) {
              return SimpleDialog(
                title: Text("Select device"),
                children: devices,
              );
            },
          ).then((value) => choice = value ?? "unknown");
        } else {
          await showDialog<String>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text("End sync"),
                actions: <Widget>[
                  ElevatedButton(
                    child: const Text("No"),
                    onPressed: () => Navigator.pop(context),
                  ),
                  ElevatedButton(
                    child: const Text("Yes"),
                    onPressed: () async {
                      Navigator.pop(context, "cancel");
                    },
                  ),
                ],
                content: const Text("Stop synchronizing with remote device?"),
              );
            },
          ).then((value) => choice = value ?? deviceManager.syncedDevice);
        }

        return choice;
      } else {
        throw Exception('Failed to load list of devices.');
      }
    } catch (e) {
      return "unknown";
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
                Navigator.pop(context, 'external');
              },
              child: const Text('Play on another device'),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context, 'edit');
              },
              child: const Text('Edit metadata'),
            ),
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
      case 'external':
        showDeviceSelectionDialog(context, false).then((value) {
          if (value != "unknown") {
            queueOnExternalDevice(
              songListNotifier.value.songList[index].filename,
              value,
            );
          }
        });
        break;
      case 'edit':
        showMetadataInputDialog(context, index);
        break;
      case 'delete':
        await apiClient.deleteSong(
          songListNotifier.value.songList[index].filename,
        );
        break;
      case null:
        // dialog dismissed
        break;
    }
  }

  Future<void> showMetadataInputDialog(BuildContext context, int index) async {
    final songToEdit = songListNotifier.value.songList[index];
    final titleTextEditingController = TextEditingController(
      text: songToEdit.title,
    );
    final artistTextEditingController = TextEditingController(
      text: songToEdit.artist,
    );
    final albumTextEditingController = TextEditingController(
      text: songToEdit.album,
    );

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit metadata"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleTextEditingController,
                decoration: InputDecoration(
                  labelText: "Title",
                  hintText: songToEdit.title,
                ),
              ),
              SizedBox(height: 14),
              TextField(
                controller: artistTextEditingController,
                decoration: InputDecoration(
                  labelText: "Artist",
                  hintText: songToEdit.artist,
                ),
              ),
              SizedBox(height: 14),
              TextField(
                controller: albumTextEditingController,
                decoration: InputDecoration(
                  labelText: "Album",
                  hintText: songToEdit.album,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            ElevatedButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text('OK'),
              onPressed: () async {
                apiClient.updateSongMetadata(
                  songListNotifier.value.songList[index].filename,
                  titleTextEditingController.text,
                  artistTextEditingController.text,
                  albumTextEditingController.text,
                );

                // Update the currently playing song,
                // since it was edited.
                if (currentIndex == index) {
                  songMetadataNotifier.value = MetadataNotifier(
                    album: albumTextEditingController.text,
                    artist: artistTextEditingController.text,
                    title: titleTextEditingController.text,
                  );
                }

                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<String?> showTextInputDialog(
    BuildContext context,
    String title,
    String hint,
  ) async {
    final textFieldController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: textFieldController,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: <Widget>[
            ElevatedButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context, textFieldController.text),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> showSyncConfirmationDialog(
    BuildContext context,
    String targetId,
  ) async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Sync request"),
          content: Text("$targetId wishes to sync with your device."),
          actions: <Widget>[
            ElevatedButton(
              child: const Text("Reject"),
              onPressed: () => Navigator.pop(context, false),
            ),
            ElevatedButton(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        );
      },
    );
  }

  Future<void> setServerHost(String url) async {
    apiClient.setApiHost(url);
    webSocketClient.setWebSocketUrl(url, "8080");

    // Re-initialize our connection
    deviceManager.getDeviceIdentifier().then((value) {
      deviceManager.registerDevice(value, apiClient);
    });
    await reconnect();
  }

  Future<void> reconnect() async {
    await registerWebSocket();
    refresh();
  }

  Future<void> registerWebSocket() async {
    try {
      await webSocketClient.connect();

      final updatesSubscription = {
        "event": "pusher:subscribe",
        "data": {"channel": "songs-updates"},
      };
      final controlsSubscription = {
        "event": "pusher:subscribe",
        "data": {"channel": "device-controls"},
      };

      await webSocketClient.subscribe(updatesSubscription);
      await webSocketClient.subscribe(controlsSubscription);

      List<String> socketChannels = ['songs-updates', 'device-controls'];
      List<String> events = [
        'update',
        'delete',
        'pause',
        'play',
        'queue',
        'seek',
        'sync-req',
        'sync-ok',
        'sync-no',
        'sync-end',
      ];

      await webSocketClient.listenTo(socketChannels, events, (
        String channel,
        dynamic eventData,
      ) async {
        if (channel == 'songs-updates') {
          switch (eventData['message']) {
            case 'update':
              // Generic update message. Refresh immediately.
              refresh();
              break;
            case 'delete':
              songListNotifier.value.songList.removeWhere(
                (item) => item.filename == eventData['filename'],
              );
              // This is so dumb, but whatever.
              songListNotifier.value = SongListState(
                songList: songListNotifier.value.songList,
              );
              break;
          }
        } else if (channel == 'device-controls') {
          if (deviceManager.deviceId.isNotEmpty) {
            var origin = eventData['origin'] == deviceManager.getUniqueId()
                ? null
                : eventData['origin'];

            if (eventData['deviceId'] == deviceManager.getUniqueId()) {
              switch (eventData['message']) {
                case 'pause':
                  pause(origin: origin);
                  break;
                case 'play':
                  play(origin: origin);
                  break;
                case 'queue':
                  var filename = eventData['filename'];
                  var index = songListNotifier.value.songList.indexWhere(
                    (item) => item.filename == eventData['filename'],
                  );
                  queue(filename, index, origin: origin);
                  break;
                case 'seek':
                  if (eventData['extra'] != null) {
                    seek(parseDuration(eventData['extra']), origin: origin);
                  }
                case 'sync-req':
                  // We received a sync request. Prompt the user first.
                  if (deviceManager.isDeviceSyncing()) {
                    // We're already synced, reject the request.
                    deviceManager.invokeDeviceCommand(
                      'sync-no',
                      origin,
                      apiClient,
                    );
                  } else if (origin != null &&
                      NavigationService.navigatorKey.currentContext != null) {
                    await showSyncConfirmationDialog(
                      NavigationService.navigatorKey.currentContext!,
                      origin,
                    ).then((accepted) {
                      if (accepted != null && accepted) {
                        deviceManager.invokeDeviceCommand(
                          'sync-ok',
                          origin,
                          apiClient,
                        );
                      } else {
                        deviceManager.invokeDeviceCommand(
                          'sync-no',
                          origin,
                          apiClient,
                        );
                      }
                    });
                  }
                case 'sync-ok':
                  // Our sync request got accepted, initialize the variables.
                  try {
                    if (!deviceManager.isDeviceSyncing()) {
                      deviceManager.syncing = true;
                      deviceManager.syncedDevice = eventData['origin'];

                      // Tell our origin that we're okay.
                      deviceManager.invokeDeviceCommand(
                        'sync-ok',
                        eventData['origin'],
                        apiClient,
                      );
                    }
                  } catch (e) {
                    // We should be fine.
                  }
                  break;
                case 'sync-no':
                case 'sync-end':
                  deviceManager.syncing = false;
                  deviceManager.syncedDevice = "";
                  break;
              }
            }
          }
        }
      });
    } catch (error) {
      // Something really bad happened.
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
