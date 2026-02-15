import 'package:flutter/material.dart';

class DetailsMetadataSection extends StatelessWidget {
  final String title;
  final String episodeInfo;
  final int? knownMaxEpisode;
  final String timeString;
  final bool showEpisodeBadge;
  final bool showTimeBadge;
  final bool hideTotalCount;
  final VoidCallback? onRename;

  const DetailsMetadataSection({
    super.key,
    required this.title,
    required this.episodeInfo,
    this.knownMaxEpisode,
    required this.timeString,
    this.showEpisodeBadge = true,
    this.showTimeBadge = true,
    this.hideTotalCount = false,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onRename != null)
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: onRename,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Umbenennen',
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (showEpisodeBadge) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  episodeInfo,
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (showTimeBadge)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeString,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
