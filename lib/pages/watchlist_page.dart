import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
    super.dispose();
  }

  void _onWatchlistChanged() {
    setState(() {});
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

  void _exportJson() async {
    final json = await widget.service.exportToJson();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Watchlist Export'),
        content: SingleChildScrollView(child: Text(json)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK'))],
      ),
    );
  }

  void _importJson() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Watchlist Import'),
        content: TextField(controller: controller, maxLines: 8, decoration: InputDecoration(labelText: 'JSON einfügen')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Abbrechen')),
          ElevatedButton(
            onPressed: () async {
              await widget.service.importFromJson(controller.text);
              Navigator.pop(ctx);
            },
            child: Text('Importieren'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Watchlist'),
        actions: [
          IconButton(icon: Icon(Icons.upload_file), onPressed: _exportJson),
          IconButton(icon: Icon(Icons.download), onPressed: _importJson),
        ],
      ),
      body: ListView.builder(
        itemCount: watchlist.entries.length,
        itemBuilder: (ctx, i) {
          final entry = watchlist.entries[i];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                // Cover image (tappable to open details)
                if (entry.imageUrl != null && entry.imageUrl!.isNotEmpty)
                  InkWell(
                    onTap: () => _openDetailsDialog(entry),
                    child: CachedNetworkImage(
                      imageUrl: entry.imageUrl!,
                      width: 96,
                      height: 120,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(width: 96, height: 120, color: Colors.grey.shade200, child: Icon(Icons.image, color: Colors.grey.shade400)),
                      errorWidget: (context, url, error) => Container(width: 96, height: 120, color: Colors.grey.shade200, child: Icon(Icons.broken_image, color: Colors.grey.shade400)),
                    ),
                  )
                else
                  InkWell(
                    onTap: () => _openDetailsDialog(entry),
                    child: Container(width: 96, height: 120, color: Colors.grey.shade200, child: Icon(Icons.image_not_supported, color: Colors.grey.shade400)),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.title, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text('Folgen: ${entry.episodesWatched}/${entry.totalEpisodes}'),
                        const SizedBox(height: 6),
                        Text('Status: ${entry.status.name}'),
                        if (entry.note != null && entry.note!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Notiz: ${entry.note}'),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () async {
                                // Edit dialog with stepper for episodes and manual total input
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
                                              note: noteController.text,
                                              rating: entry.rating,
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
                              },
                              child: Text('Bearbeiten'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                watchlist.removeEntry(entry.animeId);
                                widget.service.saveWatchlist();
                              },
                              child: Text('Entfernen', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAnime,
        child: Icon(Icons.add),
      ),
    );
  }
}
