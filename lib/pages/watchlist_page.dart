import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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

  @override
  void initState() {
    super.initState();
    watchlist = widget.service.watchlist;
    widget.service.loadWatchlist();
    watchlist.addListener(_onWatchlistChanged);
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
                  Text('$episodes', style: TextStyle(fontSize: 16)),
                  IconButton(onPressed: () => setState(() => episodes++), icon: Icon(Icons.add_circle_outline)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: Text('Gesamtfolgen')),
                  IconButton(onPressed: () { if (total>0) setState(() => total--); }, icon: Icon(Icons.remove_circle_outline)),
                  Text('$total', style: TextStyle(fontSize: 16)),
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
                // Cover image
                if (entry.imageUrl != null && entry.imageUrl!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: entry.imageUrl!,
                    width: 96,
                    height: 120,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(width: 96, height: 120, color: Colors.grey.shade200, child: Icon(Icons.image, color: Colors.grey.shade400)),
                    errorWidget: (context, url, error) => Container(width: 96, height: 120, color: Colors.grey.shade200, child: Icon(Icons.broken_image, color: Colors.grey.shade400)),
                  )
                else
                  Container(width: 96, height: 120, color: Colors.grey.shade200, child: Icon(Icons.image_not_supported, color: Colors.grey.shade400)),
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
                                // Edit dialog with stepper for episodes
                                int episodes = entry.episodesWatched;
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
                                              Text('$episodes', style: TextStyle(fontSize: 16)),
                                              IconButton(onPressed: () => setState(() => episodes++), icon: Icon(Icons.add_circle_outline)),
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
                                            entry.episodesWatched = episodes;
                                            entry.status = status;
                                            entry.note = noteController.text;
                                            watchlist.updateEntry(entry);
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
