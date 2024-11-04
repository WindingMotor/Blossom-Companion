import 'dart:typed_data';

class Music {
  final String path;
  final String folderName;
  final DateTime lastModified;
  final String title;
  final String album;
  final String artist;
  final int duration;
  final Uint8List? picture;
  final String year;
  final String genre;
  final int size;
  List<String> playlists;

  Music({
    required this.path,
    required this.folderName,
    required this.lastModified,
    required this.title,
    required this.album,
    required this.artist,
    required this.duration,
    this.picture,
    required this.year,
    required this.genre,
    required this.size,
    List<String>? playlists,
  }) : playlists = playlists ?? [];

  factory Music.fromJson(Map<String, dynamic> json) {
    return Music(
      path: json['path'],
      folderName: json['folderName'],
      lastModified: DateTime.parse(json['lastModified']),
      title: json['title'],
      album: json['album'],
      artist: json['artist'],
      duration: json['duration'],
      picture: json['picture'] != null
          ? Uint8List.fromList(List<int>.from(json['picture']))
          : null,
      year: json['year'],
      genre: json['genre'],
      size: json['size'],
      playlists: List<String>.from(json['playlists'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'folderName': folderName,
      'lastModified': lastModified.toIso8601String(),
      'title': title,
      'album': album,
      'artist': artist,
      'duration': duration,
      'picture': picture?.toList(),
      'year': year,
      'genre': genre,
      'size': size,
      'playlists': playlists,
    };
  }

  void updatePlaylists(List<String> newPlaylists) {
    playlists = List.from(newPlaylists);
  }
}
