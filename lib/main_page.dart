// main_page.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:blossomcompanion/manager/device_manager.dart';
import 'package:blossomcompanion/manager/spotdl_manager.dart';
import 'package:blossomcompanion/song_list/song_list_builder.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  late final DeviceManager _deviceManager;
  final SpotDLManager _spotDLManager = SpotDLManager();
  bool _isScanning = false;
  bool _isDownloading = false;
  String _currentDownloadingSong = '';
  int _currentSongIndex = 0;
  int _totalSongs = 0;

  @override
  void initState() {
    super.initState();
    // Initialize DeviceManager with setState and error handling callbacks
    _deviceManager = DeviceManager(
      (fn) => setState(fn),
      (error) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      ),
    );
    _scanForDevices();
  }

  @override
  void dispose() {
    _deviceManager.dispose();
    _spotDLManager.dispose();
    super.dispose();
  }

  Future<void> _scanForDevices() async {
    setState(() => _isScanning = true);
    try {
      await _deviceManager.scanForDevices();
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _downloadToCurrentDirectory(String url) async {
    if (_deviceManager.currentPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a directory first')),
      );
      return;
    }

    setState(() => _isDownloading = true);

    try {
      if (!await _spotDLManager.isSpotDLInstalled()) {
        await _spotDLManager.downloadSpotDL();
      }

      _spotDLManager.events.listen((event) {
        setState(() {
          _currentDownloadingSong = event.message;
          if (event.progress != null) {
            _currentSongIndex = (event.progress! * 100).round();
          }
        });
      });

      await _spotDLManager.runSpotDL([
        'download',
        url,
        '--output',
        _deviceManager.currentPath,
        '--format',
        'mp3',
        '--threads',
        '4',
        '--sponsor-block',
      ]);

      await _deviceManager.browseDirectory(_deviceManager.currentPath);
    } finally {
      setState(() {
        _isDownloading = false;
        _currentDownloadingSong = '';
        _currentSongIndex = 0;
        _totalSongs = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _deviceManager.isRootDirectory
              ? 'Device Detector'
              : path.basename(_deviceManager.currentPath),
        ),
        leading: !_deviceManager.isRootDirectory
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  final parentDir = path.dirname(_deviceManager.currentPath);
                  _deviceManager.browseDirectory(parentDir);
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
              if (_deviceManager.error.isNotEmpty)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(_deviceManager.error),
                  ),
                ),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: _buildDeviceList(),
                    ),
                    const VerticalDivider(),
                    Expanded(
                      flex: 2,
                      child: _buildContentView(),
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
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Devices:',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Expanded(
          child: _deviceManager.mountedDevices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.phone_iphone,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No devices found',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const Text(
                        'If the device is connected mount it and try again',
                        style: TextStyle(color: Colors.grey),
                      ),
                      // Refresh button
                      const SizedBox(height: 16),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _scanForDevices,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _deviceManager.mountedDevices.length,
                  itemBuilder: (context, index) {
                    final device = _deviceManager.mountedDevices[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.phone_iphone),
                        title: Text(device.name),
                        selected:
                            _deviceManager.selectedDevicePath == device.path,
                        onTap: () =>
                            _deviceManager.browseDirectory(device.path),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildContentView() {
    return Column(
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
              '${_deviceManager.currentDirectorySongs.length} songs, ${_deviceManager.currentDirectoryFiles.length} folders',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Column(
            children: [
              if (_deviceManager.currentDirectoryFiles.isNotEmpty) ...[
                Expanded(
                  flex: 1,
                  child: Card(
                    child: ListView.builder(
                      itemCount: _deviceManager.currentDirectoryFiles.length,
                      itemBuilder: (context, index) {
                        final directory =
                            _deviceManager.currentDirectoryFiles[index];
                        return ListTile(
                          leading: const Icon(Icons.folder),
                          title: Text(path.basename(directory.path)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deviceManager
                                .deleteFolder(directory as Directory),
                            tooltip: 'Delete folder',
                          ),
                          onTap: () =>
                              _deviceManager.browseDirectory(directory.path),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_deviceManager.currentDirectorySongs.isNotEmpty) ...[
                Expanded(
                  flex: 2,
                  child: Card(
                    child: SongListBuilder(
                      songs: _deviceManager.currentDirectorySongs,
                      orientation: MediaQuery.of(context).orientation,
                      onTap: (song) {
                        print('Selected song: ${song.title}');
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
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

  Widget _buildBottomBar() {
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.create_new_folder),
                onPressed: _showCreateFolderDialog,
                tooltip: 'New Folder',
              ),
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: _isDownloading ? null : _showDownloadDialog,
                tooltip: 'Download Song',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateFolderDialog() async {
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
      await _deviceManager.createFolder(folderName);
    }
  }

  Future<void> _showDownloadDialog() async {
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
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (url != null && url.isNotEmpty) {
      await _downloadToCurrentDirectory(url);
    }
  }
}
