import 'dart:io';
import 'dart:typed_data';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../theme/app_colors.dart';

/// Shows a frame grabbed from [file] with a play badge on top, falling
/// back to a plain tinted background if the frame can't be decoded.
class VideoThumbnailPreview extends StatefulWidget {
  const VideoThumbnailPreview({super.key, required this.file});

  final File file;

  @override
  State<VideoThumbnailPreview> createState() => _VideoThumbnailPreviewState();
}

class _VideoThumbnailPreviewState extends State<VideoThumbnailPreview> {
  late final Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = VideoThumbnail.thumbnailData(
      video: widget.file.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 300,
      quality: 60,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes, fit: BoxFit.cover)
            else
              Container(color: AppColors.primary25),
            Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  FluentIcons.play_24_filled,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
