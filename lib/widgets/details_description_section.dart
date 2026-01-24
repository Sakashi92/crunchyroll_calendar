import 'package:flutter/material.dart';

class DetailsDescriptionSection extends StatelessWidget {
  final String description;
  final bool isLoading;
  final bool isTranslating;
  final bool showGerman;
  final bool autoTranslateEnabled;
  final VoidCallback onToggleLanguage;

  const DetailsDescriptionSection({
    super.key,
    required this.description,
    required this.isLoading,
    required this.isTranslating,
    required this.showGerman,
    required this.autoTranslateEnabled,
    required this.onToggleLanguage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Handlung:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (!isLoading && description != 'Keine Beschreibung verfügbar' && autoTranslateEnabled)
              TextButton.icon(
                onPressed: isTranslating ? null : onToggleLanguage,
                icon: Icon(
                  Icons.translate,
                  size: 18,
                  color: isTranslating ? Colors.grey : Theme.of(context).colorScheme.primary,
                ),
                label: Text(
                  showGerman ? 'EN' : 'DE',
                  style: TextStyle(
                    color: isTranslating ? Colors.grey : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (isTranslating && showGerman)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Übersetze...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          )
        else
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
      ],
    );
  }
}
