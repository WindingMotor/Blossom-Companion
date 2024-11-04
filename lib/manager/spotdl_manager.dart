import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;

enum SpotDLStatus {
  idle,
  checking,
  downloading,
  installing,
  running,
  error,
  completed
}

class SpotDLEvent {
  final SpotDLStatus status;
  final String message;
  final double? progress;
  final String? error;

  SpotDLEvent({
    required this.status,
    required this.message,
    this.progress,
    this.error,
  });

  @override
  String toString() =>
      'SpotDLEvent(status: $status, message: $message, progress: $progress, error: $error)';
}

class SpotDLManager {
  static const String GITHUB_API_URL =
      'https://api.github.com/repos/spotDL/spotify-downloader/releases/latest';

  final _eventController = StreamController<SpotDLEvent>.broadcast();
  Stream<SpotDLEvent> get events => _eventController.stream;

  void _emitEvent(SpotDLStatus status, String message,
      {double? progress, String? error}) {
    _eventController.add(SpotDLEvent(
      status: status,
      message: message,
      progress: progress,
      error: error,
    ));
    print(
        'SpotDL: $message${progress != null ? ' (${(progress * 100).toStringAsFixed(1)}%)' : ''}${error != null ? ' Error: $error' : ''}');
  }

  Future<String> getSpotDLPath() async {
    _emitEvent(SpotDLStatus.checking, 'Getting SpotDL path');
    final Directory documentsDir = await getApplicationDocumentsDirectory();
    final String spotDLDir = path.join(documentsDir.path, '.spotdl');

    await Directory(spotDLDir).create(recursive: true);
    _emitEvent(
        SpotDLStatus.completed, 'SpotDL directory created at $spotDLDir');

    if (Platform.isWindows) {
      return path.join(spotDLDir, 'spotdl.exe');
    } else {
      return path.join(spotDLDir, 'spotdl');
    }
  }

  Future<String> _getLatestReleaseDownloadUrl() async {
    try {
      _emitEvent(SpotDLStatus.checking, 'Fetching latest release information');

      final response = await http.get(
        Uri.parse(GITHUB_API_URL),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to fetch latest release: HTTP ${response.statusCode}');
      }

      final Map<String, dynamic> releaseData = json.decode(response.body);
      final List<dynamic> assets = releaseData['assets'];
      String tagName = releaseData['tag_name'];

      _emitEvent(SpotDLStatus.checking, 'Found latest version: $tagName');

      if (tagName.startsWith('v')) {
        tagName = tagName.substring(1);
      }

      String assetName;
      if (Platform.isWindows) {
        assetName = 'spotdl-$tagName-win32.exe';
      } else if (Platform.isMacOS) {
        assetName = 'spotdl-$tagName-darwin';
      } else if (Platform.isLinux) {
        assetName = 'spotdl-$tagName-linux';
      } else {
        throw UnsupportedError(
            'Unsupported platform: ${Platform.operatingSystem}');
      }

      _emitEvent(SpotDLStatus.checking, 'Looking for asset: $assetName');

      final asset = assets.firstWhere(
        (asset) => asset['name'].toString() == assetName,
        orElse: () => null,
      );

      if (asset == null) {
        throw Exception(
            'Release asset not found for ${Platform.operatingSystem}');
      }

      _emitEvent(SpotDLStatus.completed, 'Found download URL for $assetName');
      return asset['browser_download_url'];
    } catch (e) {
      _emitEvent(SpotDLStatus.error, 'Failed to get download URL',
          error: e.toString());
      throw Exception('Failed to get download URL: $e');
    }
  }

  Future<void> downloadSpotDL() async {
    final String spotDLPath = await getSpotDLPath();

    if (await File(spotDLPath).exists()) {
      _emitEvent(
          SpotDLStatus.completed, 'SpotDL already installed at $spotDLPath');
      return;
    }

    try {
      final String downloadUrl = await _getLatestReleaseDownloadUrl();
      _emitEvent(SpotDLStatus.downloading, 'Downloading SpotDL');

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);

      if (response.statusCode == 200) {
        final contentLength = response.contentLength ?? 0;
        int received = 0;
        final List<int> bytes = [];

        await for (final chunk in response.stream) {
          bytes.addAll(chunk);
          received += chunk.length;
          if (contentLength > 0) {
            _emitEvent(
              SpotDLStatus.downloading,
              'Downloading SpotDL',
              progress: received / contentLength,
            );
          }
        }

        _emitEvent(SpotDLStatus.installing, 'Installing SpotDL');
        await File(spotDLPath).writeAsBytes(bytes);

        if (!Platform.isWindows) {
          _emitEvent(SpotDLStatus.installing, 'Setting executable permissions');
          await Process.run('chmod', ['+x', spotDLPath]);
        }

        final cacheDir =
            Directory(path.join(path.dirname(spotDLPath), '.spotdl-cache'));
        if (!await cacheDir.exists()) {
          await cacheDir.create();
        }

        _emitEvent(SpotDLStatus.completed, 'SpotDL installed successfully');
      } else {
        throw Exception(
            'Failed to download SpotDL: HTTP ${response.statusCode}');
      }
    } catch (e) {
      _emitEvent(SpotDLStatus.error, 'Failed to download SpotDL',
          error: e.toString());
      throw Exception('Failed to download SpotDL: $e');
    }
  }

  Future<bool> isSpotDLInstalled() async {
    _emitEvent(SpotDLStatus.checking, 'Checking if SpotDL is installed');
    final String spotDLPath = await getSpotDLPath();
    final exists = await File(spotDLPath).exists();
    _emitEvent(SpotDLStatus.completed,
        exists ? 'SpotDL is installed' : 'SpotDL is not installed');
    return exists;
  }

  Future<ProcessResult> runSpotDL(List<String> arguments) async {
    final String spotDLPath = await getSpotDLPath();

    if (!await isSpotDLInstalled()) {
      _emitEvent(SpotDLStatus.error, 'SpotDL is not installed');
      throw Exception('SpotDL is not installed. Call downloadSpotDL() first.');
    }

    _emitEvent(SpotDLStatus.running, 'Preparing SpotDL environment');
    final cacheDir =
        Directory(path.join(path.dirname(spotDLPath), '.spotdl-cache'));
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
    await cacheDir.create();

    _emitEvent(SpotDLStatus.running,
        'Running SpotDL with arguments: ${arguments.join(" ")}');

    // Use Process.start instead of Process.run to get real-time output
    final process = await Process.start(spotDLPath, arguments);

    // Handle stdout
    process.stdout.transform(utf8.decoder).listen((data) {
      _emitEvent(SpotDLStatus.running, data.trim());
    });

    // Handle stderr
    process.stderr.transform(utf8.decoder).listen((data) {
      _emitEvent(SpotDLStatus.running, data.trim(), error: 'stderr');
    });

    // Wait for the process to complete
    final exitCode = await process.exitCode;

    if (exitCode == 0) {
      _emitEvent(SpotDLStatus.completed, 'SpotDL completed successfully');
    } else {
      _emitEvent(SpotDLStatus.error, 'SpotDL failed with exit code: $exitCode');
    }

    // Return a ProcessResult-like object
    return ProcessResult(
      process.pid,
      exitCode,
      '', // stdout is already handled through the stream
      '', // stderr is already handled through the stream
    );
  }

  void dispose() {
    _eventController.close();
  }
}
