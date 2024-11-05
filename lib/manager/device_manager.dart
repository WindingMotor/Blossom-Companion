import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:blossomcompanion/models/device_info.dart';
import 'package:path/path.dart' as path;

class DeviceManager {
  final Function(VoidCallback fn) setState;
  final Function(String message) showError;

  List<DeviceInfo> mountedDevices = [];
  bool isScanning = false;
  String error = '';
  String? selectedDevicePath;
  List<FileSystemEntity> currentDirectoryFiles = [];
  String currentPath = '';
  bool isRootDirectory = true;

  DeviceManager(this.setState, this.showError);

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
    setState(() {
      selectedDevicePath = dirPath;
      currentPath = dirPath;
      isRootDirectory = dirPath == selectedDevicePath;
      error = '';
      currentDirectoryFiles.clear();
    });

    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        final List<FileSystemEntity> allEntities = await dir.list().toList();
        final directories = allEntities.whereType<Directory>().toList()
          ..sort(
              (a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

        setState(() {
          currentDirectoryFiles = directories;
        });
      } else {
        setState(() {
          error = 'Directory not accessible (is the device mounted?): $dirPath';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error accessing directory: $e';
      });
    }
  }
}
