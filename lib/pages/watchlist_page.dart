import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../models/anime_release.dart';
import '../services/crunchyroll_service.dart';
import '../widgets/anime_details_dialog.dart';
import '../models/watchlist.dart';
import '../services/watchlist_service.dart';

class WatchlistPage extends StatefulWidget {
  final WatchlistService service;
  const WatchlistPage({Key? key, required this.service}) : super(key: key);

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  late Watchlist watchlist;
  bool _fabVisible = true;
  late ScrollController _scrollController;

  Future<int?> _promptForEpisodeNumber(BuildContext ctx, String title, int initial) async {
    final controller = TextEditingController(text: initial.toString());
    return await showDialog<int?>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Folgenanzahl'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, null), child: Text('Abbrechen')),
          ElevatedButton(onPressed: () {
            final v = int.tryParse(controller.text.trim());
            Navigator.pop(dCtx, v ?? initial);
          }, child: Text('OK')),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    watchlist = widget.service.watchlist;
    widget.service.loadWatchlist();
    watchlist.addListener(_onWatchlistChanged);
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      try {
        final dirStr = _scrollController.position.userScrollDirection.toString();
        if (dirStr.contains('reverse') && _fabVisible) {
          setState(() => _fabVisible = false);
        } else if (dirStr.contains('forward') && !_fabVisible) {
          setState(() => _fabVisible = true);
        }
      } catch (e) {
        if (kDebugMode) print('ScrollController listener error: $e');
      }
    });
  }

  void _openDetailsDialog(WatchlistEntry entry) {
    final release = AnimeRelease(
      title: entry.title,
      episodeNumber: entry.episodesWatched.toString(),
      episodeTitle: '',
      releaseTime: DateTime.now(),
      imageUrl: entry.imageUrl,
      description: null,
      seriesUrl: entry.animeId,
      episodeUrl: '',
      isPremiere: false,
    );

    showDialog(
      context: context,
      builder: (ctx) => AnimeDetailsDialog(
        release: release,
        crunchyrollService: CrunchyrollService(),
        watchlistService: widget.service,
        totalEpisodes: entry.totalEpisodes,
        showTimeBadge: false,
      ),
    );
  }

  @override
  void dispose() {
    watchlist.removeListener(_onWatchlistChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onWatchlistChanged() {
    setState(() {});
  }

  String _formatAddedAt(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final date = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (date == today) return 'Hinzugefügt: heute';
    if (date == yesterday) return 'Hinzugefügt: gestern';
    return 'Hinzugefügt: ${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  void _addAnime() async {
    // Dummy dialog for adding anime
    final titleController = TextEditingController();
    int episodes = 0;
    int total = 0;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Anime hinzufügen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, decoration: InputDecoration(labelText: 'Titel')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('Gesehene Folgen')),
                  IconButton(onPressed: () { if (episodes>0) setState(() => episodes--); }, icon: Icon(Icons.remove_circle_outline)),
                  InkWell(
                    onTap: () async {
                      final v = await _promptForEpisodeNumber(context, 'Gesehene Folgen eingeben', episodes);
                      if (v != null) setState(() => episodes = v);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Text('$episodes', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  IconButton(onPressed: () => setState(() => episodes++), icon: Icon(Icons.add_circle_outline)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: Text('Gesamtfolgen')),
                  IconButton(onPressed: () { if (total>0) setState(() => total--); }, icon: Icon(Icons.remove_circle_outline)),
                  InkWell(
                    onTap: () async {
                      final v = await _promptForEpisodeNumber(context, 'Gesamtfolgen eingeben', total);
                      if (v != null) setState(() => total = v);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Text('$total', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  IconButton(onPressed: () => setState(() => total++), icon: Icon(Icons.add_circle_outline)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Abbrechen')),
            ElevatedButton(
              onPressed: () {
                final entry = WatchlistEntry(
                  animeId: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: titleController.text,
                  episodesWatched: episodes,
                  totalEpisodes: total,
                  notificationsEnabled: false,
                  addedAt: DateTime.now(),
                );
                watchlist.addEntry(entry);
                widget.service.saveWatchlist();
                Navigator.pop(ctx);
              },
              child: Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _toggleNotifications(WatchlistEntry entry, bool enabled) async {
    // Optimistic update
    final old = entry.notificationsEnabled;
    entry.notificationsEnabled = enabled;
    try {
      await widget.service.saveWatchlist();
      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) print('❌ Error toggling watchlist notifications: $e');
      entry.notificationsEnabled = old;
      if (mounted) setState(() {});
    }
  }

  Future<void> _showEditDialog(WatchlistEntry entry) async {
    int episodes = entry.episodesWatched;
    int total = entry.totalEpisodes;
    final noteController = TextEditingController(text: entry.note ?? '');
    WatchStatus status = entry.status;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Bearbeiten: ${entry.title}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Gesehene Folgen')),
                  IconButton(onPressed: () { if (episodes>0) setState(() => episodes--); }, icon: Icon(Icons.remove_circle_outline)),
                  InkWell(
                    onTap: () async {
                      final v = await _promptForEpisodeNumber(ctx, 'Gesehene Folgen eingeben', episodes);
                      if (v != null) setState(() => episodes = v);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Text('$episodes', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  IconButton(onPressed: () => setState(() => episodes++), icon: Icon(Icons.add_circle_outline)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: Text('Gesamtfolgen')),
                  IconButton(onPressed: () { if (total>0) setState(() => total--); }, icon: Icon(Icons.remove_circle_outline)),
                  InkWell(
                    onTap: () async {
                      final v = await _promptForEpisodeNumber(ctx, 'Gesamtfolgen eingeben', total);
                      if (v != null) setState(() => total = v);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Text('$total', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  IconButton(onPressed: () => setState(() => total++), icon: Icon(Icons.add_circle_outline)),
                ],
              ),
              DropdownButton<WatchStatus>(
                value: status,
                items: WatchStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.name))).toList(),
                onChanged: (s) { if (s != null) setState(() => status = s); },
              ),
              TextField(controller: noteController, decoration: InputDecoration(labelText: 'Notiz')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Abbrechen')),
            ElevatedButton(
              onPressed: () {
                final newEntry = WatchlistEntry(
                  animeId: entry.animeId,
                  title: entry.title,
                  imageUrl: entry.imageUrl,
                  episodesWatched: episodes,
                  totalEpisodes: total,
                  status: status,
                  notificationsEnabled: entry.notificationsEnabled,
                  note: noteController.text,
                  rating: entry.rating,
                  addedAt: entry.addedAt,
                );
                watchlist.updateEntry(newEntry);
                widget.service.saveWatchlist();
                Navigator.pop(ctx);
              },
              child: Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
  void _exportJson() async {
    if (watchlist.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Keine Einträge zum Exportieren'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      final jsonString = await widget.service.exportToJson();

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final suggestedFileName = 'crunchyroll_watchlist_$timestamp.json';
      final bytes = utf8.encode(jsonString);

      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Watchlist exportieren',
        fileName: suggestedFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      if (outputPath == null) return; // user cancelled

      if (mounted) {
        final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Export erfolgreich'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${watchlist.entries.length} Einträge exportiert'),
                const SizedBox(height: 8),
                const Text(
                  'Gespeichert unter:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(outputPath, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, 'close'), child: const Text('Schließen')),
              ElevatedButton.icon(onPressed: () => Navigator.pop(context, 'share'), icon: const Icon(Icons.share), label: const Text('Teilen')),
            ],
          ),
        );

        if (result == 'share') {
          try {
            await Share.shareXFiles([XFile(outputPath)], subject: 'Meine Crunchyroll Watchlist', text: 'Crunchyroll Watchlist (${watchlist.entries.length} Einträge)');
          } catch (e) {
            if (kDebugMode) print('Share error: $e');
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Fehler beim Teilen: $e')));
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Export error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Fehler beim Exportieren: $e'), duration: const Duration(seconds: 3), backgroundColor: Colors.red.shade700));
    }
  }

  void _importJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Watchlist-Datei auswählen',
      );

      if (result == null || result.files.isEmpty) return; // cancelled

      final filePath = result.files.single.path;
      if (filePath == null) throw Exception('Kein Dateipfad erhalten');

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Importiere Watchlist...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final importedCount = await widget.service.importFromJsonFilePath(filePath);

      if (mounted) Navigator.pop(context); // close loading

      if (importedCount > 0) {
        if (mounted) showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 8), Text('Import erfolgreich')],
            ),
            content: Text(importedCount == 1 ? '1 neuer Eintrag wurde importiert' : '$importedCount neue Einträge wurden importiert'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      } else {
        if (mounted) showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [Icon(Icons.info, color: Colors.orange), SizedBox(width: 8), Text('Keine neuen Einträge')],
            ),
            content: const Text('Die Datei wurde eingelesen, jedoch wurden keine neuen Einträge hinzugefügt.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      // close loading dialog if open
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (kDebugMode) print('Import error: $e');
      if (mounted) showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(children: [Icon(Icons.error, color: Colors.red), SizedBox(width: 8), Text('Import fehlgeschlagen')]),
          content: Text('Fehler beim Importieren:\n\n$e', style: const TextStyle(fontSize: 13)),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Watchlist'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        toolbarHeight: 48,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Händisch hinzufügen',
            onPressed: _addAnime,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Optionen',
            onSelected: (value) {
              if (value == 'export') {
                _exportJson();
              } else if (value == 'import') {
                _importJson();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.upload_file),
                    SizedBox(width: 12),
                    Text('Exportieren'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.download),
                    SizedBox(width: 12),
                    Text('Importieren'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView.builder(
        controller: _scrollController,
        itemCount: watchlist.entries.length,
        itemBuilder: (ctx, i) {
          final entry = watchlist.entries[i];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 185,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // Cover image (tappable to open details)
                if (entry.imageUrl != null && entry.imageUrl!.isNotEmpty)
                  InkWell(
                    onTap: () => _openDetailsDialog(entry),
                    child: Container(
                      width: 120,
                      padding: const EdgeInsets.only(top: 0.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: entry.imageUrl!,
                              width: 120,
                              height: 133,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => SizedBox(width: 120, height: 138, child: Container(color: Colors.grey.shade200, child: Icon(Icons.image, color: Colors.grey.shade400))),
                              errorWidget: (context, url, error) => SizedBox(width: 120, height: 138, child: Container(color: Colors.grey.shade200, child: Icon(Icons.broken_image, color: Colors.grey.shade400))),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Transform.translate(
                            offset: const Offset(0, -2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    entry.notificationsEnabled ? Icons.notifications_active : Icons.notifications_off,
                                    color: entry.notificationsEnabled ? Theme.of(context).colorScheme.primary : Colors.grey,
                                    size: 20,
                                  ),
                                  tooltip: entry.notificationsEnabled ? 'Push deaktivieren' : 'Push aktivieren',
                                  onPressed: () => _toggleNotifications(entry, !entry.notificationsEnabled),
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  tooltip: 'Bearbeiten',
                                  onPressed: () => _showEditDialog(entry),
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  InkWell(
                    onTap: () => _openDetailsDialog(entry),
                    child: Container(
                      width: 120,
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(width: 120, height: 138, child: Container(color: Colors.grey.shade200, child: Icon(Icons.image_not_supported, color: Colors.grey.shade400))),
                          ),
                          const SizedBox(height: 4),
                          Transform.translate(
                            offset: const Offset(0, -2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    entry.notificationsEnabled ? Icons.notifications_active : Icons.notifications_off,
                                    color: entry.notificationsEnabled ? Theme.of(context).colorScheme.primary : Colors.grey,
                                    size: 20,
                                  ),
                                  tooltip: entry.notificationsEnabled ? 'Push deaktivieren' : 'Push aktivieren',
                                  onPressed: () => _toggleNotifications(entry, !entry.notificationsEnabled),
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  tooltip: 'Bearbeiten',
                                  onPressed: () => _showEditDialog(entry),
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6.0, bottom: 2.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.title, style: Theme.of(context).textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('Folgen: ${entry.episodesWatched}/${entry.totalEpisodes}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('Status: ${entry.status.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (entry.note != null && entry.note!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Notiz: ${entry.note}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 6),
                        if ((entry.addedAt) != null) ...[
                          Text(
                            _formatAddedAt(entry.addedAt),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error, size: 20),
                                tooltip: 'Entfernen',
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Eintrag entfernen'),
                                      content: Text('Möchtest du "${entry.title}" wirklich aus der Watchlist entfernen?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: Text('Entfernen', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    watchlist.removeEntry(entry.animeId);
                                    await widget.service.saveWatchlist();
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eintrag entfernt'), duration: Duration(seconds: 2)));
                                  }
                                },
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ));
        },
      ),
      // FloatingActionButton removed; '+' added to AppBar actions.
    );
  }
}
