class Song {
  final String title;
  final String artist;
  final String album;
  final String duration;
  final String filename;

  const Song({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.filename,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'title': String title,
        'artist': String artist,
        'album': String album,
        'duration': String duration,
        'filename': String filename,
      } =>
        Song(
          title: title,
          artist: artist,
          album: album,
          duration: duration,
          filename: filename,
        ),
      _ => throw const FormatException('Failed to load song.'),
    };
  }
}