import 'dart:async';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_spacing.dart';

/// Plays a video document with its own controls: play/pause (replay at the
/// end), skip back/forward 10 seconds, a seek bar with elapsed and total
/// time, playback speed and mute.
///
/// Tapping the video shows or hides the controls; they hide on their own
/// a few seconds into playback. Double-tapping the left or right half skips
/// back or forward, like most video apps.
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({super.key, required this.file});

  final File file;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  static const _skip = Duration(seconds: 10);
  static const _hideAfter = Duration(seconds: 3);
  static const _speeds = [0.5, 1.0, 1.25, 1.5, 2.0];

  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// Position under the finger while dragging the seek bar.
  Duration? _scrubTo;
  bool _wasPlayingBeforeScrub = false;

  /// "+10s" / "-10s" bubble after a double-tap, and which side it's on.
  String? _skipLabel;
  bool _skipOnRight = true;
  Timer? _skipLabelTimer;
  Offset? _doubleTapAt;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)..addListener(_onTick);
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _ready = true);
        })
        .catchError((Object e) {
          if (!mounted) return;
          setState(() => _error = e.toString());
        });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _skipLabelTimer?.cancel();
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  VideoPlayerValue get _value => _controller.value;

  bool get _finished =>
      _value.duration > Duration.zero &&
      !_value.isPlaying &&
      _value.position >= _value.duration;

  void _onTick() {
    if (!mounted) return;
    if (_value.hasError && _error == null) {
      _error = _value.errorDescription ?? 'Playback failed';
    }
    // Playback ended: bring the controls back for the replay button.
    if (_finished && !_controlsVisible) _controlsVisible = true;
    setState(() {});
  }

  // --- Controls visibility ---------------------------------------------------

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  /// Hides the controls after a while, but only while playing - paused
  /// video keeps them up.
  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_value.isPlaying) return;
    _hideTimer = Timer(_hideAfter, () {
      if (mounted && _value.isPlaying && _scrubTo == null) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  // --- Playback --------------------------------------------------------------

  Future<void> _togglePlay() async {
    if (_value.isPlaying) {
      await _controller.pause();
    } else {
      if (_finished) await _controller.seekTo(Duration.zero);
      await _controller.play();
    }
    _showControls();
  }

  Future<void> _seekBy(Duration offset) async {
    final target = _value.position + offset;
    await _controller.seekTo(_clamp(target));
    _showControls();
  }

  Duration _clamp(Duration d) {
    if (d < Duration.zero) return Duration.zero;
    if (d > _value.duration) return _value.duration;
    return d;
  }

  void _onDoubleTap() {
    final at = _doubleTapAt;
    if (at == null) return;
    final width = context.size?.width ?? 0;
    final forward = at.dx > width / 2;
    _seekBy(forward ? _skip : -_skip);
    _skipLabelTimer?.cancel();
    setState(() {
      _skipOnRight = forward;
      _skipLabel = forward ? '+10s' : '-10s';
    });
    _skipLabelTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _skipLabel = null);
    });
  }

  Future<void> _cycleSpeed() async {
    final i = _speeds.indexOf(_value.playbackSpeed);
    final next = _speeds[(i + 1) % _speeds.length];
    await _controller.setPlaybackSpeed(next);
    _showControls();
  }

  Future<void> _toggleMute() async {
    await _controller.setVolume(_value.volume == 0 ? 1 : 0);
    _showControls();
  }

  void _onScrubStart(double ms) {
    _hideTimer?.cancel();
    _wasPlayingBeforeScrub = _value.isPlaying;
    _controller.pause();
    setState(() => _scrubTo = Duration(milliseconds: ms.round()));
  }

  void _onScrub(double ms) {
    final to = Duration(milliseconds: ms.round());
    setState(() => _scrubTo = to);
    // Local files seek fast enough to show the frame while dragging.
    _controller.seekTo(to);
  }

  Future<void> _onScrubEnd(double ms) async {
    await _controller.seekTo(Duration(milliseconds: ms.round()));
    if (_wasPlayingBeforeScrub) await _controller.play();
    if (!mounted) return;
    setState(() => _scrubTo = null);
    _scheduleHide();
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                FluentIcons.video_off_24_regular,
                color: Colors.white70,
                size: 40,
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                'Could not play this video.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    if (!_ready) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          // Tap anywhere toggles the controls; double-tap a side to skip.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
            onDoubleTap: _onDoubleTap,
          ),
          if (_skipLabel != null)
            Align(
              alignment: _skipOnRight
                  ? const Alignment(0.6, 0)
                  : const Alignment(-0.6, 0),
              child: IgnorePointer(child: _SkipBubble(label: _skipLabel!)),
            ),
          IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: _buildControls(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final duration = _value.duration;
    final position = _scrubTo ?? _clamp(_value.position);
    final muted = _value.volume == 0;
    final speed = _value.playbackSpeed;
    final timeStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Colors.white,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // Darkens the bottom so the white controls read on bright video.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.5, 1],
                colors: [Colors.transparent, Color(0xAA000000)],
              ),
            ),
          ),
        ),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundButton(
                tooltip: 'Back 10 seconds',
                icon: FluentIcons.skip_back_10_28_regular,
                size: 52,
                onPressed: () => _seekBy(-_skip),
              ),
              const SizedBox(width: AppSpacing.s7),
              _RoundButton(
                tooltip: _value.isPlaying
                    ? 'Pause'
                    : _finished
                    ? 'Replay'
                    : 'Play',
                icon: _value.isPlaying
                    ? FluentIcons.pause_48_filled
                    : _finished
                    ? FluentIcons.arrow_counterclockwise_48_filled
                    : FluentIcons.play_48_filled,
                size: 72,
                onPressed: _togglePlay,
              ),
              const SizedBox(width: AppSpacing.s7),
              _RoundButton(
                tooltip: 'Forward 10 seconds',
                icon: FluentIcons.skip_forward_10_28_regular,
                size: 52,
                onPressed: () => _seekBy(_skip),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                0,
                AppSpacing.s2,
                AppSpacing.s2,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                    ),
                    child: Slider(
                      min: 0,
                      max: duration.inMilliseconds
                          .toDouble()
                          .clamp(1, double.infinity)
                          .toDouble(),
                      value: position.inMilliseconds
                          .clamp(0, duration.inMilliseconds)
                          .toDouble(),
                      onChangeStart: _onScrubStart,
                      onChanged: _onScrub,
                      onChangeEnd: _onScrubEnd,
                    ),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: AppSpacing.s4),
                      Text(
                        '${_format(position, duration)} / '
                        '${_format(duration, duration)}',
                        style: timeStyle,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _cycleSpeed,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          minimumSize: const Size(48, 40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s3,
                          ),
                        ),
                        child: Text(
                          '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
                          style: timeStyle,
                        ),
                      ),
                      IconButton(
                        tooltip: muted ? 'Unmute' : 'Mute',
                        onPressed: _toggleMute,
                        color: Colors.white,
                        icon: Icon(
                          muted
                              ? FluentIcons.speaker_mute_24_regular
                              : FluentIcons.speaker_2_24_regular,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// m:ss, or h:mm:ss when the video is an hour or longer.
  static String _format(Duration d, Duration total) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return total.inHours > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.size,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, color: Colors.white, size: size * 0.5),
          ),
        ),
      ),
    );
  }
}

class _SkipBubble extends StatelessWidget {
  const _SkipBubble({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s5,
        vertical: AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
