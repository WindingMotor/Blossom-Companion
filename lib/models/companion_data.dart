// models/companion_data.dart
class CompanionData {
  final DateTime currentTime;
  final bool connected;
  final bool isDownloading;
  final String? currentDownloadingSong;
  final int? downloadProgress;
  final int? totalSongs;
  final String? lastError;

  CompanionData({
    required this.currentTime,
    required this.connected,
    required this.isDownloading,
    this.currentDownloadingSong,
    this.downloadProgress,
    this.totalSongs,
    this.lastError,
  });

  Map<String, dynamic> toJson() => {
        'current_time': currentTime.toIso8601String(),
        'connected': connected,
        'is_downloading': isDownloading,
        'current_downloading_song': currentDownloadingSong,
        'download_progress': downloadProgress,
        'total_songs': totalSongs,
        'last_error': lastError,
      };

  factory CompanionData.fromJson(Map<String, dynamic> json) {
    return CompanionData(
      currentTime: DateTime.parse(json['current_time']),
      connected: json['connected'] ?? false,
      isDownloading: json['is_downloading'] ?? false,
      currentDownloadingSong: json['current_downloading_song'],
      downloadProgress: json['download_progress'],
      totalSongs: json['total_songs'],
      lastError: json['last_error'],
    );
  }
}
