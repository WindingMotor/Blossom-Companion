import 'dart:async';
import 'package:flutter/material.dart';
import 'package:blossomcompanion/utils/music.dart';
import 'package:blossomcompanion/song_list/song_list_tile_wrapper.dart';

class SongListBuilder extends StatefulWidget {
  final List<Music> songs;
  final void Function(Music)? onTap;
  final Orientation? orientation;

  const SongListBuilder({
    Key? key,
    required this.songs,
    this.onTap,
    required this.orientation,
  }) : super(key: key);

  @override
  SongListBuilderState createState() => SongListBuilderState();
}

class SongListBuilderState extends State<SongListBuilder> {
  ScrollController _scrollController = ScrollController();
  Timer? _scrollDebounce;
  double _scrollVelocity = 0.0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _debouncedScroll(void Function() callback) {
    if (_scrollDebounce?.isActive ?? false) _scrollDebounce!.cancel();

    int debounceDuration = _calculateDebounceDuration(_scrollVelocity);
    _scrollDebounce = Timer(Duration(milliseconds: debounceDuration), callback);
  }

  int _calculateDebounceDuration(double velocity) {
    int baseDuration = 15;

    if (velocity > 2500) {
      return (baseDuration * 3).round();
    } else if (velocity > 100) {
      return (baseDuration * 1.5).round();
    } else if (velocity > 20) {
      return baseDuration;
    } else {
      return (baseDuration * 0.75).round();
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      _scrollVelocity = notification.scrollDelta?.abs() ?? 0.0;
      _debouncedScroll(() {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (notification is ScrollEndNotification) {
      _scrollVelocity = 0.0;
      if (mounted) {
        setState(() {});
      }
    }
    return false;
  }

  void scrollToPosition(double position) {
    _scrollController.animateTo(
      position,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: widget.songs.length,
          itemExtent: 80,
          itemBuilder: (BuildContext context, int index) {
            final song = widget.songs[index];
            return SongListTileWrapper(
              key: ValueKey(song.path),
              song: song,
              isCurrentSong: false,
              isSelected: false,
              onTap: () => _handleTap(song),
              onLongPress: () {},
            );
          },
        ),
      ),
    );
  }

  void _handleTap(Music song) {
    if (widget.onTap != null) {
      widget.onTap!(song);
    }
  }
}
