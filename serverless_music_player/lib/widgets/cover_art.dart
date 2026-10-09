import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/song_model.dart';
import '../theme/app_theme.dart';

class CoverArt extends StatelessWidget {
  const CoverArt({
    required this.song,
    this.size = 56,
    this.radius = 15,
    super.key,
  });

  final SongModel song;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final localPath = song.localArtworkPath;
    final image = localPath != null && localPath.isNotEmpty && File(localPath).existsSync()
        ? Image.file(File(localPath), fit: BoxFit.cover)
        : song.artworkUrl.startsWith('http')
            ? CachedNetworkImage(
                imageUrl: song.artworkUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => _placeholder(context),
                errorWidget: (_, __, ___) => _placeholder(context),
              )
            : _placeholder(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: image),
    );
  }

  Widget _placeholder(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            palette.accent.withValues(alpha: 0.28),
            palette.mint.withValues(alpha: 0.22),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.music_note_rounded, color: palette.mint),
    );
  }
}
