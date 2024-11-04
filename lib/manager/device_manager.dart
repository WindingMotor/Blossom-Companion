// device_manager.dart
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:path/path.dart' as path;
import 'package:metadata_god/metadata_god.dart';
import 'package:blossomcompanion/models/device_info.dart';
import 'package:blossomcompanion/models/music.dart';
import 'package:blossomcompanion/models/companion_data.dart';

class DeviceManager {
  final Function(VoidCallback fn) setState;
  final Function(String message) showError;

  // State variables
  List<DeviceInfo> mountedDevices = [];
  bool isScanning = false;
  bool isLoading = false;
  String error = '';
  String? selectedDevicePath;
  List<FileSystemEntity> currentDirectoryFiles = [];
  List<Music> currentDirectorySongs = [];
  String currentPath = '';
  bool isRootDirectory = true;
  int totalSongs = 0;
  int currentSongIndex = 0;
  String currentDownloadingSong = '';
  bool isDownloading = false;
  Timer? companionUpdateTimer;

  DeviceManager(this.setState, this.showError) {
    _startCompanionUpdates();
  }

  void _startCompanionUpdates() {
    companionUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (selectedDevicePath != null) {
        updateCompanionFile();
      }
    });
  }

  void dispose() {
    companionUpdateTimer?.cancel();
  }

  Future<void> updateCompanionFile() async {
    if (selectedDevicePath == null) return;

    try {
      final companionData = CompanionData(
        currentTime: DateTime.now(),
        connected: true,
        isDownloading: isDownloading,
        currentDownloadingSong: currentDownloadingSong,
        downloadProgress: currentSongIndex,
        totalSongs: totalSongs,
        lastError: error.isNotEmpty ? error : null,
      );

      final companionFile =
          File(path.join(selectedDevicePath!, 'companion.json'));

      // Create parent directories if they don't exist
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

  Future<void> scanForDevices() async {
    setState(() {
      isScanning = true;
      error = '';
      mountedDevices.clear();
    });

    try {
      if (Platform.isLinux) {
        await _scanLinux();
      } else if (Platform.isWindows) {
        await _scanWindows();
      } else {
        setState(() {
          error = 'Unsupported platform';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error scanning for devices: $e';
      });
    } finally {
      setState(() {
        isScanning = false;
      });
    }
  }

  Future<void> _scanLinux() async {
    try {
      final result = await Process.run('lsusb', []);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');

        for (var line in lines) {
          if (line.toLowerCase().contains('apple')) {
            final deviceInfo = DeviceInfo(
              name: line,
              id: line.split(' ')[1],
              path:
                  '/run/user/1000/gvfs/afc:host=${line.split(' ')[1]},port=3/com.wmstudios.blossom',
            );
            setState(() {
              mountedDevices.add(deviceInfo);
            });
          }
        }
      }

      const gvfsPath = '/run/user/1000/gvfs';
      if (await Directory(gvfsPath).exists()) {
        final gvfsDir = Directory(gvfsPath);
        await for (final entity in gvfsDir.list()) {
          if (entity.path.contains('afc:host=')) {
            final deviceInfo = DeviceInfo(
              name: 'iOS Device (${path.basename(entity.path)})',
              id: path.basename(entity.path),
              path: '${entity.path}/com.wmstudios.blossom',
            );
            setState(() {
              mountedDevices.add(deviceInfo);
            });
          }
        }
      }
    } catch (e) {
      setState(() {
        error = 'Error scanning Linux devices: $e';
      });
    }
  }

  Future<void> _scanWindows() async {
    try {
      final result = await Process.run('powershell', [
        '-Command',
        r'Get-PnpDevice | Where-Object {$_.Class -eq "Portable Devices" -or $_.Class -eq "Apple Mobile Device"}'
      ]);

      if (result.exitCode == 0) {
        final devices = (result.stdout as String)
            .split('\n')
            .where((line) => line.toLowerCase().contains('apple'))
            .map((line) => DeviceInfo(
                  name: line.trim(),
                  id: 'windows_device',
                  path: r'\\?\Apple\iPod\',
                ))
            .toList();

        setState(() {
          mountedDevices.addAll(devices);
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error scanning Windows devices: $e';
      });
    }
  }

  Future<void> browseDirectory(String dirPath) async {
    final wasConnected = selectedDevicePath != null;
    final newConnection = !wasConnected || selectedDevicePath != dirPath;

    setState(() {
      selectedDevicePath = dirPath;
      currentPath = dirPath;
      isRootDirectory = dirPath == selectedDevicePath;
      error = '';
      currentDirectoryFiles = [];
      currentDirectorySongs = [];
    });

    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        if (newConnection) {
          await updateCompanionFile();
        }

        final List<FileSystemEntity> allEntities = await dir.list().toList();

        final directories = allEntities.whereType<Directory>().toList()
          ..sort(
              (a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

        setState(() {
          currentDirectoryFiles = directories;
        });

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
              await Future.wait(chunk.map((file) => _processAudioFile(file)));

          songs.addAll(chunkResults.whereType<Music>());

          setState(() {
            currentDirectorySongs = List.from(songs)
              ..sort((a, b) => a.title.compareTo(b.title));
          });
        }
      } else {
        setState(() {
          error = 'Directory not accessible: $dirPath';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error accessing directory: $e';
      });
    }
  }

  Future<Music?> _processAudioFile(File file) async {
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
      await browseDirectory(currentPath);
    } catch (e) {
      showError('Error creating folder: $e');
    }
  }

  Future<void> deleteFolder(Directory directory) async {
    try {
      setState(() {
        isLoading = true;
      });

      await directory.delete(recursive: true);
      await browseDirectory(currentPath);
    } catch (e) {
      showError('Error deleting folder: $e');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }
}
