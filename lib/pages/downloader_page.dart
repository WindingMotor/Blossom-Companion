import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

class DownloaderController extends ChangeNotifier {
  List<String> _currentlyDownloading = [];
  List<String> get currentlyDownloading => _currentlyDownloading;

  void addDownloadingFile(String filename) {
    _currentlyDownloading.add(filename);
    notifyListeners();
  }

  void removeDownloadingFile(String filename) {
    _currentlyDownloading.remove(filename);
    notifyListeners();
  }
}

class DownloaderPage extends StatefulWidget {
  const DownloaderPage({super.key});

  @override
  _DownloaderPageState createState() => _DownloaderPageState();
}

class _DownloaderPageState extends State<DownloaderPage> {
  String _output = '';
  bool _isLoading = false;
  bool _ffmpegInstalled = false;
  bool _spotdlInstalled = false;
  final TextEditingController _urlController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final DownloaderController _downloaderController = DownloaderController();
  bool _isUrlValid = false;

  @override
  void initState() {
    super.initState();
    _setupEnvironment();
    _urlController.addListener(_validateUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _validateUrl() {
    final url = _urlController.text.trim();
    setState(() {
      _isUrlValid = url.isNotEmpty &&
          (url.startsWith('https://open.spotify.com/') ||
              url.startsWith('spotify:'));
    });
  }

  Future<void> _setupEnvironment() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _output = 'Setting up environment...\n';
    });

    try {
      await _checkFFmpegInstallation();
      await _setupSpotDL();
    } catch (e) {
      if (mounted) {
        setState(() => _output += 'Unexpected error: $e\n');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _checkFFmpegInstallation() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      if (result.exitCode == 0) {
        setState(() {
          _ffmpegInstalled = true;
          _output += 'FFmpeg is installed and ready to use.\n';
        });
      } else {
        setState(() {
          _ffmpegInstalled = false;
          _output += 'FFmpeg is not installed.\n';
        });
      }
    } catch (e) {
      setState(() {
        _ffmpegInstalled = false;
        _output += 'Error checking FFmpeg installation: $e\n';
      });
    }
  }

  Future<void> _setupSpotDL() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final venvPath = '${documentsDir.path}/blossom_venv';

    // Check if python3 is installed
    try {
      final pythonCheckResult = await Process.run('python3', ['--version']);
      if (pythonCheckResult.exitCode != 0) {
        if (mounted) {
          setState(() =>
              _output += 'Error: Python3 is not installed or not in PATH.\n');
        }
        return;
      }
    } catch (e) {
      try {
        final pythonCheckResult = await Process.run('python', ['--version']);
        if (pythonCheckResult.exitCode != 0) {
          if (mounted) {
            setState(() =>
                _output += 'Error: Python is not installed or not in PATH.\n');
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          setState(() =>
              _output += 'Error: Python is not installed or not in PATH.\n');
        }
        return;
      }
    }

    // Create virtual environment
    final venvDir = Directory(venvPath);
    if (!await venvDir.exists()) {
      final venvResult = await Process.run('python3', ['-m', 'venv', venvPath]);
      if (venvResult.exitCode != 0) {
        if (mounted) {
          setState(() => _output +=
              'Error creating virtual environment: ${venvResult.stderr}\n');
        }
        return;
      }
      if (mounted) {
        setState(() => _output += 'Virtual environment created.\n');
      }
    } else {
      if (mounted) {
        setState(() => _output += 'Virtual environment already exists.\n');
      }
    }

    if (mounted) {
      setState(() => _output +=
          'Checking if spotdl is installed. If not wait for it to download.\n');
    }

    // Install spotdl
    final pipPath =
        Platform.isWindows ? '$venvPath\\Scripts\\pip' : '$venvPath/bin/pip';
    final spotdlInstallResult =
        await Process.run(pipPath, ['install', 'spotdl']);
    if (spotdlInstallResult.exitCode != 0) {
      if (mounted) {
        setState(() => _output +=
            'Error installing spotdl: ${spotdlInstallResult.stderr}\n');
      }
      return;
    }

    if (mounted) {
      setState(() {
        _output += 'spotdl installed successfully.\n';
        _spotdlInstalled = true;
      });
    }
  }

  void _showFFmpegInstructions() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Install FFmpeg'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Please install FFmpeg for your system:'),
                const SizedBox(height: 16),
                if (Platform.isWindows)
                  _InstructionCard(
                    title: 'Windows Installation',
                    instructions: [
                      'Download FFmpeg from the official website',
                      'Extract the archive',
                      'Add FFmpeg to your system PATH',
                    ],
                  ),
                if (Platform.isMacOS)
                  _InstructionCard(
                    title: 'macOS Installation',
                    instructions: [
                      'Install Homebrew if not already installed',
                      'Run: brew install ffmpeg',
                    ],
                    command: 'brew install ffmpeg',
                  ),
                if (Platform.isLinux)
                  _InstructionCard(
                    title: 'Linux Installation',
                    instructions: [
                      'Use your package manager to install FFmpeg',
                    ],
                    command: 'sudo apt install ffmpeg',
                  ),
                const SizedBox(height: 16),
                const Text('After installation, click "Confirm" below.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                launchUrl(Uri.parse('https://ffmpeg.org/download.html'));
              },
              child: const Text('Open FFmpeg Website'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _checkFFmpegInstallation();
              },
              child: const Text('Confirm Installation'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadPlaylist() async {
    if (!_isUrlValid) {
      _showErrorSnackBar('Please enter a valid Spotify URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _output += 'Starting download...\n';
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
        [
          _urlController.text,
          '--output',
          songDir,
          '--format',
          'mp3',
          '--threads',
          '4',
          '--sponsor-block',
        ],
      );

      process.stdout.transform(utf8.decoder).listen((data) {
        setState(() {
          _output += data;
          _scrollToBottom();
        });

        _processDownloadOutput(data);
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        setState(() {
          _output += 'Error: $data';
          _scrollToBottom();
        });
      });

      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        setState(() => _output += 'Download completed successfully!\n');
        _showSuccessDialog();
      } else {
        setState(
            () => _output += 'Error during download. Exit code: $exitCode\n');
        _showErrorSnackBar('Download failed. Please check the logs.');
      }
    } catch (e) {
      setState(() => _output += 'Error during download: $e\n');
      _showErrorSnackBar('Download failed. Please check the logs.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _processDownloadOutput(String data) {
    final downloadingMatch =
        RegExp(r'Downloading: (.*?\.mp3)').firstMatch(data);
    if (downloadingMatch != null) {
      _downloaderController.addDownloadingFile(downloadingMatch.group(1)!);
    }

    final downloadedMatch = RegExp(r'Downloaded: (.*?\.mp3)').firstMatch(data);
    if (downloadedMatch != null) {
      _downloaderController.removeDownloadingFile(downloadedMatch.group(1)!);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Download Complete'),
          content: const Text(
              'Your music has been downloaded successfully. The library will be updated when you return.'),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _copyOutput() {
    Clipboard.setData(ClipboardData(text: _output));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Log copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download Music'),
        actions: [
          if (_output.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copyOutput,
              tooltip: 'Copy log',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildUrlInput(),
                  const SizedBox(height: 16),
                  _buildStatusCard(),
                ],
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildUrlInput() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Spotify URL',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'Enter Spotify playlist, album, or track URL',
                prefixIcon: const Icon(Icons.link),
                suffixIcon: _urlController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _urlController.clear();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                enabled: _ffmpegInstalled && _spotdlInstalled && !_isLoading,
              ),
              enabled: _ffmpegInstalled && _spotdlInstalled && !_isLoading,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Status Log',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_output.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: _copyOutput,
                    tooltip: 'Copy log',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(8),
                child: SelectableText(_output),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    if (!_ffmpegInstalled) {
      return FloatingActionButton.extended(
        onPressed: _showFFmpegInstructions,
        label: const Text('Install FFmpeg'),
        icon: const Icon(Icons.download),
      );
    }

    if (!_spotdlInstalled || _isLoading) {
      return const FloatingActionButton.extended(
        onPressed: null,
        label: Text('Please wait...'),
        icon: Icon(Icons.hourglass_empty),
      );
    }

    return FloatingActionButton.extended(
      onPressed: _isUrlValid ? _downloadPlaylist : null,
      label: const Text('Download'),
      icon: const Icon(Icons.download),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  final String title;
  final List<String> instructions;
  final String? command;

  const _InstructionCard({
    required this.title,
    required this.instructions,
    this.command,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...instructions.map((instruction) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(instruction)),
                    ],
                  ),
                )),
            if (command != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        command!,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: command!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Command copied to clipboard'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      tooltip: 'Copy command',
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
