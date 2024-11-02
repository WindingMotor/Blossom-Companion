import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:metadata_god/metadata_god.dart';
import 'package:blossomcompanion/utils/music.dart';
import 'package:blossomcompanion/song_list/song_list_builder.dart';
import 'package:path_provider/path_provider.dart';

class DeviceDetector extends StatefulWidget {
  const DeviceDetector({super.key});

  @override
  _DeviceDetectorState createState() => _DeviceDetectorState();
}

class _DeviceDetectorState extends State<DeviceDetector> {
  List<DeviceInfo> _mountedDevices = [];
  bool _isScanning = false;
  bool _isLoading = false;
  String _error = '';
  String? _selectedDevicePath;
  List<FileSystemEntity> _currentDirectoryFiles = [];
  List<Music> _currentDirectorySongs = [];
  String _currentPath = '';
  bool _isRootDirectory = true;
  int _totalSongs = 0;
  int _currentSongIndex = 0;
  String _currentDownloadingSong = '';
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _scanForDevices();
  }

  Future<void> _scanForDevices() async {
    setState(() {
      _isScanning = true;
      _error = '';
      _mountedDevices.clear();
    });

    try {
      if (Platform.isLinux) {
        await _scanLinux();
      } else if (Platform.isWindows) {
        await _scanWindows();
      } else {
        setState(() {
          _error = 'Unsupported platform';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error scanning for devices: $e';
      });
    } finally {
      setState(() {
        _isScanning = false;
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
              _mountedDevices.add(deviceInfo);
            });
          }
        }
      }

      final gvfsPath = '/run/user/1000/gvfs';
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
              _mountedDevices.add(deviceInfo);
            });
          }
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Error scanning Linux devices: $e';
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
          _mountedDevices.addAll(devices);
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error scanning Windows devices: $e';
      });
    }
  }

  Future<void> _downloadToCurrentDirectory(String url) async {
    if (_currentPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a directory first')),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _currentSongIndex = 0;
      _totalSongs = 0;
      _currentDownloadingSong = 'Processing query...';
    });

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final venvPath = '${documentsDir.path}/blossom_venv';
      final spotdlPath = Platform.isWindows
          ? '$venvPath\\Scripts\\spotdl'
          : '$venvPath/bin/spotdl';

      final process = await Process.start(
        spotdlPath,
        [
          url,
          '--output',
          _currentPath,
          '--format',
          'mp3',
          '--threads',
          '4',
          '--sponsor-block',
        ],
      );

      process.stdout.transform(utf8.decoder).listen((data) {
        final lines = data.split('\n');
        for (var line in lines) {
          // Match total songs in playlist
          final playlistMatch = RegExp(r'Found (\d+) songs').firstMatch(line);
          if (playlistMatch != null) {
            setState(() {
              _totalSongs = int.parse(playlistMatch.group(1) ?? '0');
            });
          }

          // Match downloaded song
          final downloadMatch =
              RegExp(r'Downloaded "([^"]+)"').firstMatch(line);
          if (downloadMatch != null) {
            setState(() {
              _currentSongIndex++;
              _currentDownloadingSong =
                  downloadMatch.group(1) ?? 'Unknown Song';
            });
          }

          // Match progress line
          final progressMatch =
              RegExp(r'(\d+)/(\d+) complete').firstMatch(line);
          if (progressMatch != null) {
            setState(() {
              _currentSongIndex = int.parse(progressMatch.group(1) ?? '0');
              _totalSongs = int.parse(progressMatch.group(2) ?? '0');
            });
          }
        }
      });

      // Also listen to stderr for errors
      process.stderr.transform(utf8.decoder).listen((data) {
        if (data.contains('FFmpegError')) {
          print('FFmpeg Error: $data');
        }
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        await _browseDirectory(_currentPath);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download completed successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isDownloading = false;
        _currentDownloadingSong = '';
        _currentSongIndex = 0;
        _totalSongs = 0;
      });
    }
  }

  Widget _buildDownloadProgress() {
    if (!_isDownloading) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          if (_totalSongs > 0) ...[
            Text(
              '$_currentSongIndex/$_totalSongs',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              _currentDownloadingSong,
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createNewFolder() async {
    final controller = TextEditingController();
    final folderName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter folder name',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (folderName != null && folderName.isNotEmpty) {
      final newFolderPath = path.join(_currentPath, folderName);
      try {
        await Directory(newFolderPath).create();
        await _browseDirectory(_currentPath);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating folder: $e')),
        );
      }
    }
  }

  Future<Music> _createMusicFromFile(File file) async {
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
        picture: _extractPicture(metadata),
        year: metadata.year?.toString() ?? '',
        genre: metadata.genre ?? '',
        size: fileStats.size,
      );
    } catch (e) {
      return Music(
        path: file.path,
        folderName: path.basename(path.dirname(file.path)),
        lastModified: await file.lastModified(),
        title: path.basenameWithoutExtension(file.path),
        album: 'Unknown Album',
        artist: 'Unknown Artist',
        duration: 0,
        picture: null,
        year: '',
        genre: '',
        size: await file.length(),
      );
    }
  }

  Uint8List? _extractPicture(Metadata metadata) {
    if (metadata.picture != null) {
      return Uint8List.fromList(metadata.picture!.data);
    }
    return null;
  }

  Future<void> _browseDirectory(String dirPath) async {
    setState(() {
      _selectedDevicePath = dirPath;
      _currentPath = dirPath;
      _isRootDirectory = dirPath == _selectedDevicePath;
      _error = '';
      _currentDirectoryFiles = [];
      _currentDirectorySongs = [];
    });

    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        final List<FileSystemEntity> allEntities = await dir.list().toList();

        final directories = allEntities.whereType<Directory>().toList()
          ..sort(
              (a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

        setState(() {
          _currentDirectoryFiles = directories;
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

          if (mounted) {
            setState(() {
              _currentDirectorySongs = List.from(songs)
                ..sort((a, b) => a.title.compareTo(b.title));
            });
          }
        }
      } else {
        setState(() {
          _error = 'Directory not accessible: $dirPath';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error accessing directory: $e';
        });
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _isRootDirectory ? 'Device Detector' : path.basename(_currentPath)),
        leading: !_isRootDirectory
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  final parentDir = path.dirname(_currentPath);
                  _browseDirectory(parentDir);
                },
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _scanForDevices,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isScanning)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_error.isNotEmpty)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(_error),
                  ),
                ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Devices:',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Expanded(
                            child: _buildDeviceList(),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Contents:',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                '${_currentDirectorySongs.length} songs, ${_currentDirectoryFiles.length} folders',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _buildContentView(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDownloadProgress(),
          BottomAppBar(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _browseDirectory(_currentPath),
                  tooltip: 'Refresh',
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.create_new_folder),
                      onPressed: _createNewFolder,
                      tooltip: 'New Folder',
                    ),
                    IconButton(
                      icon: const Icon(Icons.download),
                      onPressed: _isDownloading
                          ? null
                          : () async {
                              final controller = TextEditingController();
                              final url = await showDialog<String>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Download Song'),
                                  content: TextField(
                                    controller: controller,
                                    decoration: const InputDecoration(
                                      hintText: 'Enter song URL',
                                    ),
                                    onSubmitted: (value) =>
                                        Navigator.of(context).pop(value),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.of(context)
                                          .pop(controller.text),
                                      child: const Text('Download'),
                                    ),
                                  ],
                                ),
                              );
                              if (url != null && url.isNotEmpty) {
                                await _downloadToCurrentDirectory(url);
                              }
                            },
                      tooltip: 'Download Song',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return _mountedDevices.isEmpty
        ? const Center(child: Text('No iOS devices detected'))
        : ListView.builder(
            itemCount: _mountedDevices.length,
            itemBuilder: (context, index) {
              final device = _mountedDevices[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.phone_iphone),
                  title: Text(device.name),
                  selected: _selectedDevicePath == device.path,
                  onTap: () => _browseDirectory(device.path),
                ),
              );
            },
          );
  }

  Widget _buildContentView() {
    return Column(
      children: [
        if (_currentDirectoryFiles.isNotEmpty) ...[
          Expanded(
            flex: 1,
            child: Card(
              child: ListView.builder(
                itemCount: _currentDirectoryFiles.length,
                itemBuilder: (context, index) {
                  final directory = _currentDirectoryFiles[index];
                  return ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(path.basename(directory.path)),
                    onTap: () => _browseDirectory(directory.path),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_currentDirectorySongs.isNotEmpty) ...[
          Expanded(
            flex: 2,
            child: Card(
              child: SongListBuilder(
                songs: _currentDirectorySongs,
                orientation: MediaQuery.of(context).orientation,
                onTap: (song) {
                  print('Selected song: ${song.title}');
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class DeviceInfo {
  final String name;
  final String id;
  final String path;

  DeviceInfo({
    required this.name,
    required this.id,
    required this.path,
  });
}
