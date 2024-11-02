import 'dart:async';
import 'package:blossomcompanion/metadata.dart';
import 'package:blossomcompanion/pages/downloader_page.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class SongListPage extends StatefulWidget {
  const SongListPage({Key? key}) : super(key: key);

  @override
  _SongListPageState createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  List<FileSystemEntity> _downloadedSongs = [];
  List<FileSystemEntity> _filteredSongs = [];
  List<String> _downloadingFiles = [];
  Timer? _refreshTimer;
  final _downloader = DownloaderController();
  String _searchQuery = '';
  String _sortBy = 'title';
  bool _sortAscending = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSongs();
    _startRefreshTimer();
    _downloader.addListener(_onDownloadUpdate);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _downloader.removeListener(_onDownloadUpdate);
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _loadSongs();
    });
  }

  void _onDownloadUpdate() {
    setState(() {
      _downloadingFiles = _downloader.currentlyDownloading;
    });
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
        _downloadedSongs = files;
        _filterAndSortSongs();
      });
    }
  }

  Future<void> _filterAndSortSongs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Filter songs
      if (_searchQuery.isEmpty) {
        _filteredSongs = List.from(_downloadedSongs);
      } else {
        _filteredSongs = [];
        for (var file in _downloadedSongs) {
          final metadata = await MetadataHandler.loadMetadata(file.path);
          final searchLower = _searchQuery.toLowerCase();
          if (metadata['title']
                  .toString()
                  .toLowerCase()
                  .contains(searchLower) ||
              metadata['artist']
                  .toString()
                  .toLowerCase()
                  .contains(searchLower) ||
              metadata['album']
                  .toString()
                  .toLowerCase()
                  .contains(searchLower)) {
            _filteredSongs.add(file);
          }
        }
      }

      // Sort songs
      List<MapEntry<FileSystemEntity, Map<String, dynamic>>> songsWithMetadata =
          [];
      for (var file in _filteredSongs) {
        final metadata = await MetadataHandler.loadMetadata(file.path);
        songsWithMetadata.add(MapEntry(file, metadata));
      }

      songsWithMetadata.sort((a, b) {
        String valueA = '';
        String valueB = '';

        switch (_sortBy) {
          case 'title':
            valueA = a.value['title'].toString();
            valueB = b.value['title'].toString();
            break;
          case 'artist':
            valueA = a.value['artist'].toString();
            valueB = b.value['artist'].toString();
            break;
          case 'album':
            valueA = a.value['album'].toString();
            valueB = b.value['album'].toString();
            break;
          case 'year':
            valueA = a.value['year'].toString();
            valueB = b.value['year'].toString();
            break;
        }

        return _sortAscending
            ? valueA.compareTo(valueB)
            : valueB.compareTo(valueA);
      });

      setState(() {
        _filteredSongs = songsWithMetadata.map((e) => e.key).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('Error filtering and sorting songs: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  PopupMenuItem<String> _buildPopupMenuItem(String value, IconData icon) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(_capitalize(value)),
        ],
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: const InputDecoration(
            hintText: 'Search songs...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
              _filterAndSortSongs();
            });
          },
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort by',
            onSelected: (String value) {
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
            itemBuilder: (BuildContext context) {
              return [
                _buildPopupMenuItem('title', Icons.abc_rounded),
                _buildPopupMenuItem('artist', Icons.person_rounded),
                _buildPopupMenuItem('album', Icons.album_rounded),
                _buildPopupMenuItem('year', Icons.calendar_today_rounded),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_downloadingFiles.isNotEmpty)
            Card(
              margin: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'Currently Downloading',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _downloadingFiles.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        leading: const CircularProgressIndicator(),
                        title: Text(path.basename(_downloadingFiles[index])),
                      );
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSongs.isEmpty
                    ? const Center(child: Text('No songs found'))
                    : ListView.builder(
                        itemCount: _filteredSongs.length,
                        itemBuilder: (context, index) {
                          final file = _filteredSongs[index];
                          return FutureBuilder<Map<String, dynamic>>(
                            future: MetadataHandler.loadMetadata(file.path),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const ListTile(
                                  leading: CircularProgressIndicator(),
                                  title: Text('Loading...'),
                                );
                              }

                              final metadata = snapshot.data!;
                              return ListTile(
                                leading: metadata['picture'] != null
                                    ? Image.memory(
                                        metadata['picture'],
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                      )
                                    : const Icon(Icons.music_note),
                                title: Text(metadata['title']),
                                subtitle: Text(metadata['artist']),
                                trailing: IconButton(
                                  icon: const Icon(Icons.more_vert),
                                  onPressed: () => _showOptions(context, file),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const DownloaderPage(),
            ),
          );
          if (result == true) {
            _loadSongs();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showOptions(BuildContext context, FileSystemEntity file) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Metadata'),
                onTap: () {
                  Navigator.pop(context);
                  _editMetadata(file as File);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Delete'),
                onTap: () async {
                  Navigator.pop(context);
                  await file.delete();
                  _loadSongs();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editMetadata(File file) async {
    final metadata = await MetadataHandler.loadMetadata(file.path);

    final titleController = TextEditingController(text: metadata['title']);
    final artistController = TextEditingController(text: metadata['artist']);
    final albumController = TextEditingController(text: metadata['album']);
    final genreController = TextEditingController(text: metadata['genre']);
    final yearController = TextEditingController(text: metadata['year']);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Metadata'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: artistController,
                  decoration: const InputDecoration(labelText: 'Artist'),
                ),
                TextField(
                  controller: albumController,
                  decoration: const InputDecoration(labelText: 'Album'),
                ),
                TextField(
                  controller: genreController,
                  decoration: const InputDecoration(labelText: 'Genre'),
                ),
                TextField(
                  controller: yearController,
                  decoration: const InputDecoration(labelText: 'Year'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final updates = {
                  'title': titleController.text,
                  'artist': artistController.text,
                  'album': albumController.text,
                  'genre': genreController.text,
                  'year': yearController.text,
                };

                await MetadataHandler.updateMetadata(file.path, updates);
                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}
