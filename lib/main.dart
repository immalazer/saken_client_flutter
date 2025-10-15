import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'page_manager.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final PageManager _pageManager;

  @override
  void initState() {
    super.initState();
    _pageManager = PageManager();
  }

  @override
  void dispose() {
    _pageManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Saken',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.purple,
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(title: Text("Saken"), centerTitle: true),
        body: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                const Spacer(),
                ValueListenableBuilder<SongListState>(
                  valueListenable: _pageManager.songListNotifier,
                  builder: (_, value, _) {
                    return SizedBox(
                      height: MediaQuery.of(context).size.height * 0.65,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: value.songList.length,
                        itemBuilder: (BuildContext context, int index) {
                          return Column(
                            children: [
                              ListTile(
                                onLongPress: () {
                                  _pageManager.showSongOptionDialog(context, index);
                                },
                                onTap: () {
                                  _pageManager.queue(
                                    value.songList[index].filename,
                                    index,
                                  );
                                },
                                leading: FutureBuilder(
                                  future: _pageManager.getAlbumArt(index),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData) {
                                      return CircleAvatar(
                                        foregroundImage: NetworkImage(
                                          snapshot.data!,
                                        ),
                                      );
                                    } else {
                                      return CircleAvatar(
                                        child: Text(value.songList[index].title[0]),
                                      );
                                    }
                                  },
                                ),
                                title: Text(value.songList[index].title),
                                subtitle: Text(
                                  "${value.songList[index].artist}\n${value.songList[index].album}",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w200,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                              Divider(),
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
                const Spacer(),
                ValueListenableBuilder<MetadataNotifier>(
                  valueListenable: _pageManager.songMetadataNotifier,
                  builder: (_, value, _) {
                    return Column(
                      children: [
                        Text(
                          value.title!,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Center(
                          child: Text(
                            value.artist!,
                            style: TextStyle(fontWeight: FontWeight.w200),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                ValueListenableBuilder<ProgressBarState>(
                  valueListenable: _pageManager.progressNotifier,
                  builder: (_, value, _) {
                    return ProgressBar(
                      progress: value.current,
                      buffered: value.buffered,
                      total: value.total,
                      onSeek: _pageManager.seek,
                    );
                  },
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.speaker_rounded),
                      tooltip: "Output",
                      onPressed: () {
                      }),
                    const Spacer(),
                    Row(
                      children: [
                        IconButton(
                          tooltip: "Rewind",
                          onPressed: () {
                            _pageManager.rewind();
                          },
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        ValueListenableBuilder<ButtonState>(
                          valueListenable: _pageManager.buttonNotifier,
                          builder: (_, value, _) {
                            switch (value) {
                              case ButtonState.loading:
                                return Container(
                                  margin: const EdgeInsets.all(8.0),
                                  width: 32.0,
                                  height: 32.0,
                                  child: const CircularProgressIndicator(),
                                );
                              case ButtonState.paused:
                                return IconButton(
                                  tooltip: "Play",
                                  icon: const Icon(Icons.play_arrow),
                                  iconSize: 32.0,
                                  onPressed: _pageManager.play,
                                );
                              case ButtonState.playing:
                                return IconButton(
                                  tooltip: "Pause",
                                  icon: const Icon(Icons.pause),
                                  iconSize: 32.0,
                                  onPressed: _pageManager.pause,
                                );
                            }
                          },
                        ),
                        IconButton(
                          tooltip: "Skip",
                          onPressed: () {
                            _pageManager.fastForward();
                          },
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      ],
                    ),
                    const Spacer(),
                    PopupMenuButton(
                      icon: Icon(Icons.more_vert_rounded),
                      tooltip: "More options",
                      onSelected: (value) async {
                        switch (value) {
                          case 'refresh':
                            _pageManager.refresh();
                            break;
                          case 'upload':
                            _pageManager.uploadSong();
                            break;
                          case 'server':
                            var resultLabel = await _pageManager
                                .showTextInputDialog(
                                  context,
                                  "Configure server host",
                                  _pageManager.host,
                                );
                            if (resultLabel != null) {
                              _pageManager.setServerHost(resultLabel);
                            }
                            break;
                        }
                      },
                      itemBuilder: (BuildContext context) {
                        return [
                          PopupMenuItem<String>(
                            value: 'refresh',
                            child: Text('Refresh'),
                          ),
                          PopupMenuItem<String>(
                            value: 'upload',
                            child: Text('Upload'),
                          ),
                          PopupMenuItem<String>(
                            value: 'server',
                            child: Text('Server'),
                          ),
                        ];
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
