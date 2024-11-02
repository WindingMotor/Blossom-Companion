import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

class MusicLibraryPage extends StatefulWidget {
  const MusicLibraryPage({super.key});

  @override
  _MusicLibraryPageState createState() => _MusicLibraryPageState();
}

class _MusicLibraryPageState extends State<MusicLibraryPage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<FileSystemEntity> _songs = [];
  List<FileSystemEntity> _filteredSongs = [];
  List<String> _currentlyDownloading = [];
  String _downloadOutput = '';
  bool _isDownloading = false;
  bool _ffmpegInstalled = false;
  bool _spotdlInstalled = false;
  String _sortBy = 'title';
  bool _sortAscending = true;
  bool _showDownloader = false;

  @override
  void initState() {
    super.initState();
    _setupEnvironment();
    _loadSongs();
    _urlController.addListener(_validateUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _setupEnvironment() async {
    await _checkFFmpegInstallation();
    await _setupSpotDL();
  }

  Future<void> _checkFFmpegInstallation() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      setState(() => _ffmpegInstalled = result.exitCode == 0);
    } catch (e) {
      setState(() => _ffmpegInstalled = false);
    }
  }

  Future<void> _setupSpotDL() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final venvPath = '${documentsDir.path}/blossom_venv';

    try {
      final pythonResult = await Process.run('python3', ['--version']);
      if (pythonResult.exitCode != 0) throw Exception('Python not found');

      // Create virtual environment if it doesn't exist
      final venvDir = Directory(venvPath);
      if (!await venvDir.exists()) {
        await Process.run('python3', ['-m', 'venv', venvPath]);
      }

      // Install spotdl
      final pipPath =
          Platform.isWindows ? '$venvPath\\Scripts\\pip' : '$venvPath/bin/pip';
      final installResult = await Process.run(pipPath, ['install', 'spotdl']);
      setState(() => _spotdlInstalled = installResult.exitCode == 0);
    } catch (e) {
      setState(() => _spotdlInstalled = false);
    }
  }

  void _validateUrl() {
    setState(() {});
  }

  Future<void> _loadSongs() async {
    final dir = await getApplicationDocumentsDirectory();
    final songDir = Directory('${dir.path}/songs');

    if (await songDir.exists()) {
      final files = await songDir
          .list()
          .where((entity) =>
              entity is File &&
              path.extension(entity.path).toLowerCase() == '.mp3')
          .toList();

      setState(() {
        _songs = files;
        _filterAndSortSongs();
      });
    }
  }

  void _filterAndSortSongs() {
    var filtered = List<FileSystemEntity>.from(_songs);
    final query = _searchController.text.toLowerCase();

    if (query.isNotEmpty) {
      filtered = filtered.where((file) {
        final name = path.basename(file.path).toLowerCase();
        return name.contains(query);
      }).toList();
    }

    filtered.sort((a, b) {
      final nameA = path.basename(a.path);
      final nameB = path.basename(b.path);
      return _sortAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
    });

    setState(() => _filteredSongs = filtered);
  }

  Future<void> _downloadMusic() async {
    if (!_ffmpegInstalled || !_spotdlInstalled) return;

    setState(() {
      _isDownloading = true;
      _downloadOutput = 'Starting download...\n';
    });

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final venvPath = '${documentsDir.path}/blossom_venv';
      final spotdlPath = Platform.isWindows
          ? '$venvPath\\Scripts\\spotdl'
          : '$venvPath/bin/spotdl';
      final songDir = '${documentsDir.path}/songs';

      final downloadDirectory = Directory(songDir);
      if (!await downloadDirectory.exists()) {
        await downloadDirectory.create(recursive: true);
      }

      final process = await Process.start(
        spotdlPath,
        [_urlController.text, '--output', songDir, '--format', 'mp3'],
      );

      process.stdout.transform(utf8.decoder).listen((data) {
        setState(() => _downloadOutput += data);
        _processDownloadOutput(data);
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        setState(() => _downloadOutput += 'Error: $data');
      });

      final exitCode = await process.exitCode;
      if (exitCode == 0) {
        setState(() => _downloadOutput += 'Download completed successfully!\n');
        await _loadSongs();
      }
    } catch (e) {
      setState(() => _downloadOutput += 'Error: $e\n');
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  void _processDownloadOutput(String data) {
    final downloadingMatch =
        RegExp(r'Downloading: (.*?\.mp3)').firstMatch(data);
    if (downloadingMatch != null) {
      setState(() => _currentlyDownloading.add(downloadingMatch.group(1)!));
    }

    final downloadedMatch = RegExp(r'Downloaded: (.*?\.mp3)').firstMatch(data);
    if (downloadedMatch != null) {
      setState(() => _currentlyDownloading.remove(downloadedMatch.group(1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 250,
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.library_music),
                  title: const Text('Library'),
                  selected: !_showDownloader,
                  onTap: () => setState(() => _showDownloader = false),
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Download'),
                  selected: _showDownloader,
                  onTap: () => setState(() => _showDownloader = true),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search library...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _filterAndSortSongs(),
                  ),
                ),
              ],
            ),
          ),
          // Main content
          Expanded(
            child: _showDownloader ? _buildDownloader() : _buildLibrary(),
          ),
        ],
      ),
      floatingActionButton: !_showDownloader
          ? FloatingActionButton(
              onPressed: _loadSongs,
              child: const Icon(Icons.refresh),
            )
          : null,
    );
  }

  Widget _buildDownloader() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Download Music',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Spotify URL',
                      hintText: 'Enter Spotify playlist, album, or track URL',
                      border: OutlineInputBorder(),
                    ),
                    enabled:
                        _ffmpegInstalled && _spotdlInstalled && !_isDownloading,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isDownloading ? null : _downloadMusic,
                    icon: const Icon(Icons.download),
                    label: Text(_isDownloading ? 'Downloading...' : 'Download'),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_currentlyDownloading.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              child: Column(
                children: _currentlyDownloading
                    .map((file) => ListTile(
                          leading: const CircularProgressIndicator(),
                          title: Text(path.basename(file)),
                        ))
                    .toList(),
              ),
            ),
          ),
        if (_downloadOutput.isNotEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: SelectableText(_downloadOutput),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLibrary() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.sort),
                tooltip: 'Sort by',
                onSelected: (value) {
                  setState(() {
                    if (_sortBy == value) {
                      _sortAscending = !_sortAscending;
                    } else {
                      _sortBy = value;
                      _sortAscending = true;
                    }
                    _filterAndSortSongs();
                  });
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'title', child: Text('Title')),
                  const PopupMenuItem(value: 'artist', child: Text('Artist')),
                  const PopupMenuItem(value: 'album', child: Text('Album')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredSongs.length,
            itemBuilder: (context, index) {
              final file = _filteredSongs[index];
              return ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(path.basenameWithoutExtension(file.path)),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showSongOptions(context, file),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showSongOptions(BuildContext context, FileSystemEntity file) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Metadata'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement metadata editing
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete'),
              onTap: () async {
                await file.delete();
                Navigator.pop(context);
                _loadSongs();
              },
            ),
          ],
        ),
      ),
    );
  }
}
