class Song implements Comparable<Song> {
  final String title;
  final String artists;
  final String album;
  final String duration;
  final String filename;

  const Song({
    required this.title,
    required this.artists,
    required this.album,
    required this.duration,
    required this.filename,
  });

  @override
  int compareTo(Song other) {
    // Compare by title
    final titleComparison = title.toLowerCase().compareTo(other.title.toLowerCase());
    
    if (titleComparison != 0) {
      return titleComparison;
    }

    // If titles are the same, compare by artist
    return artists.toLowerCase().compareTo(other.artists.toLowerCase());
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'title': String title,
        'artists': String artists,
        'album': String album,
        'duration': String duration,
        'filename': String filename,
      } =>
        Song(
          title: title,
          artists: artists,
          album: album,
          duration: duration,
          filename: filename,
        ),
      _ => throw const FormatException('Failed to load song.'),
    };
  }
}
