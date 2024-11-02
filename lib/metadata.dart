import 'dart:io';
import 'dart:typed_data';
import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart' as path;

class MetadataHandler {
  static Future<Map<String, dynamic>> loadMetadata(String filePath) async {
    try {
      final metadata = await MetadataGod.readMetadata(file: filePath);
      final file = File(filePath);
      final fileStat = await file.stat();

      return {
        'path': filePath,
        'folderName': path.basename(path.dirname(filePath)),
        'lastModified': fileStat.modified,
        'title': metadata.title ?? path.basenameWithoutExtension(filePath),
        'album': metadata.album ?? 'Unknown Album',
        'artist': metadata.artist ?? 'Unknown Artist',
        'duration': metadata.durationMs?.round() ?? 0,
        'picture': metadata.picture?.data,
        'year': metadata.year?.toString() ?? '',
        'genre': metadata.genre ?? 'Unknown Genre',
        'size': fileStat.size,
      };
    } catch (e) {
      print('Error reading metadata for $filePath: $e');
      // Return basic file information if metadata reading fails
      final file = File(filePath);
      final fileStat = await file.stat();

      return {
        'path': filePath,
        'folderName': path.basename(path.dirname(filePath)),
        'lastModified': fileStat.modified,
        'title': path.basenameWithoutExtension(filePath),
        'album': 'Unknown Album',
        'artist': 'Unknown Artist',
        'duration': 0,
        'picture': null,
        'year': '',
        'genre': 'Unknown Genre',
        'size': fileStat.size,
      };
    }
  }

  static Future<bool> writeMetadata({
    required String filePath,
    required String title,
    String? artist,
    String? album,
    String? genre,
    int? year,
    int? trackNumber,
    Uint8List? artwork,
  }) async {
    try {
      final metadata = Metadata(
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        year: year,
        trackNumber: trackNumber,
        picture: artwork != null
            ? Picture(
                data: artwork,
                mimeType: 'image/jpeg',
              )
            : null,
      );

      await MetadataGod.writeMetadata(
        file: filePath,
        metadata: metadata,
      );
      return true;
    } catch (e) {
      print('Error writing metadata for $filePath: $e');
      return false;
    }
  }

  static Future<bool> updateMetadata(
      String filePath, Map<String, dynamic> updates) async {
    try {
      final currentMetadata = await MetadataGod.readMetadata(file: filePath);

      final metadata = Metadata(
        title: updates['title'] ?? currentMetadata.title,
        artist: updates['artist'] ?? currentMetadata.artist,
        album: updates['album'] ?? currentMetadata.album,
        genre: updates['genre'] ?? currentMetadata.genre,
        year: updates['year'] != null
            ? int.tryParse(updates['year'])
            : currentMetadata.year,
        trackNumber: updates['trackNumber'] ?? currentMetadata.trackNumber,
        picture: updates['picture'] != null
            ? Picture(
                data: updates['picture'],
                mimeType: 'image/jpeg',
              )
            : currentMetadata.picture,
      );

      await MetadataGod.writeMetadata(
        file: filePath,
        metadata: metadata,
      );
      return true;
    } catch (e) {
      print('Error updating metadata for $filePath: $e');
      return false;
    }
  }

  static Future<Uint8List?> extractArtwork(String filePath) async {
    try {
      final metadata = await MetadataGod.readMetadata(file: filePath);
      return metadata.picture?.data;
    } catch (e) {
      print('Error extracting artwork from $filePath: $e');
      return null;
    }
  }
}
