import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:path/path.dart' as path;
import 'package:metadata_god/metadata_god.dart';
import 'package:blossomcompanion/models/music.dart';
import 'package:blossomcompanion/models/companion_data.dart';

class FileManager {
  final Function(VoidCallback fn) setState;
  final Function(String message) showError;

  List<Music> currentDirectorySongs = [];
  bool isDownloading = false;
  String currentDownloadingSong = '';
  int currentSongIndex = 0;
  int totalSongs = 0;
  Timer? companionUpdateTimer;

  FileManager(this.setState, this.showError) {
    _startCompanionUpdates();
  }

  void _startCompanionUpdates() {
    companionUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (currentPath.isNotEmpty) {
        updateCompanionFile();
      }
    });
  }

  void dispose() {
    companionUpdateTimer?.cancel();
  }

  String currentPath = '';

  Future<void> updateCompanionFile() async {
    try {
      final companionData = CompanionData(
        currentTime: DateTime.now(),
        connected: true,
        isDownloading: isDownloading,
        currentDownloadingSong: currentDownloadingSong,
        downloadProgress: currentSongIndex,
        totalSongs: totalSongs,
        lastError: null,
      );

      final companionFile = File(path.join(currentPath, 'companion.json'));

      if (!await companionFile.parent.exists()) {
        await companionFile.parent.create(recursive: true);
      }

      await companionFile.writeAsString(
        jsonEncode(companionData.toJson()),
        flush: true,
      );
    } catch (e) {
      print('Error updating companion file: $e');
    }
  }

  Future<void> loadDirectory(String dirPath) async {
    setState(() {
      currentPath = dirPath;
      currentDirectorySongs.clear();
    });

    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        final List<FileSystemEntity> allEntities = await dir.list().toList();

        final audioFiles = allEntities.whereType<File>().where((file) {
          final ext = path.extension(file.path).toLowerCase();
          return ext == '.mp3' || ext == '.flac';
        }).toList();

        const chunkSize = 20;
        final songs = <Music>[];

        for (var i = 0; i < audioFiles.length; i += chunkSize) {
          final end = (i + chunkSize < audioFiles.length)
              ? i + chunkSize
              : audioFiles.length;
          final chunk = audioFiles.sublist(i, end);

          final chunkResults =
              await Future.wait(chunk.map((file) => processAudioFile(file)));

          songs.addAll(chunkResults.whereType<Music>());

          setState(() {
            currentDirectorySongs = List.from(songs)
              ..sort((a, b) => a.title.compareTo(b.title));
          });
        }
      }
    } catch (e) {
      showError('Error loading directory: $e');
    }
  }

  Future<Music?> processAudioFile(File file) async {
    try {
      final metadata = await MetadataGod.readMetadata(file: file.path);
      final fileStats = await file.stat();

      return Music(
        path: file.path,
        folderName: path.basename(path.dirname(file.path)),
        lastModified: fileStats.modified,
        title: metadata.title ?? path.basenameWithoutExtension(file.path),
        album: metadata.album ?? 'Unknown Album',
        artist: metadata.artist ?? 'Unknown Artist',
        duration: metadata.duration?.inMilliseconds ?? 0,
        picture: metadata.picture?.data,
        year: metadata.year?.toString() ?? '',
        genre: metadata.genre ?? '',
        size: fileStats.size,
      );
    } catch (e) {
      print('Error processing file ${file.path}: $e');
      return null;
    }
  }

  Future<void> createFolder(String folderName) async {
    if (currentPath.isEmpty) return;

    final newFolderPath = path.join(currentPath, folderName);
    try {
      await Directory(newFolderPath).create();
      await loadDirectory(currentPath);
    } catch (e) {
      showError('Error creating folder: $e');
    }
  }

  Future<void> deleteFolder(Directory directory) async {
    try {
      setState(() {
        isDownloading = true;
      });

      await directory.delete(recursive: true);
      await loadDirectory(currentPath);
    } catch (e) {
      showError('Error deleting folder: $e');
    } finally {
      setState(() {
        isDownloading = false;
      });
    }
  }
}
