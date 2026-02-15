import 'package:flutter/material.dart';
import '../services/backup_service.dart';

class ImportSelectionDialog extends StatefulWidget {
  final Map<String, dynamic> backupData;

  const ImportSelectionDialog({super.key, required this.backupData});

  @override
  State<ImportSelectionDialog> createState() => _ImportSelectionDialogState();
}

class _ImportSelectionDialogState extends State<ImportSelectionDialog> {
  final Map<String, bool> _selectedCategories = {};
  final Map<String, String> _categoryNames = {
    BackupService.catSettings: 'Einstellungen',
    BackupService.catWatchlist: 'Watchlist',
    BackupService.catCustomTitles: 'Benutzerdefinierte Titel',
    BackupService.catSeenReleases: 'Gesehene Folgen',
    BackupService.catHistory: 'Suchverlauf',
    BackupService.catCalendarCache: 'Kalender-Cache (Offline Daten)',
    BackupService.catHiddenAnime: 'Versteckte Anime',
  };

  @override
  void initState() {
    super.initState();
    final data = widget.backupData['data'] as Map<String, dynamic>;
    for (var cat in _categoryNames.keys) {
      if (data.containsKey(cat)) {
        _selectedCategories[cat] = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Daten importieren'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Wähle aus, welche Bereiche du wiederherstellen möchtest:',
            ),
            const SizedBox(height: 16),
            ..._selectedCategories.keys.map((cat) {
              return CheckboxListTile(
                title: Text(_categoryNames[cat] ?? cat),
                value: _selectedCategories[cat],
                onChanged: (bool? value) {
                  setState(() {
                    _selectedCategories[cat] = value ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                dense: true,
              );
            }),
            if (_selectedCategories.isEmpty)
              const Text(
                'Keine importierbaren Daten in dieser Datei gefunden.',
                style: TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: _selectedCategories.values.contains(true)
              ? () {
                  final result = _selectedCategories.entries
                      .where((e) => e.value)
                      .map((e) => e.key)
                      .toList();
                  Navigator.pop(context, result);
                }
              : null,
          child: const Text('Importieren'),
        ),
      ],
    );
  }
}
