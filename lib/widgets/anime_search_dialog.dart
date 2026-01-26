import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/anime_metadata.dart';
import '../services/episode_provider.dart';
import '../services/episode_provider_factory.dart';

/// A generic dialog to search and select an anime from the configured database.
class AnimeSearchDialog extends StatefulWidget {
  final String initialQuery;
  final String? title;

  const AnimeSearchDialog({super.key, required this.initialQuery, this.title});

  @override
  State<AnimeSearchDialog> createState() => _AnimeSearchDialogState();
}

class _AnimeSearchDialogState extends State<AnimeSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  List<AnimeMetadata> _results = [];
  bool _isLoading = false;
  String? _error;
  EpisodeProvider? _provider;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    _initProvider();
  }

  Future<void> _initProvider() async {
    _provider = await EpisodeProviderFactory.getProvider();
    if (widget.initialQuery.isNotEmpty) {
      _search();
    }
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _provider == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _results = [];
    });

    try {
      final results = await _provider!.searchSeries(query);
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
          if (results.isEmpty) _error = 'Keine Ergebnisse gefunden';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Fehler bei der Suche';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxHeight: 600, maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title ?? 'Anime Suche',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Nach Name suchen',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
            else if (_results.isNotEmpty)
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (ctx, i) => const Divider(),
                  itemBuilder: (ctx, i) {
                    final meta = _results[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: meta.imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: meta.imageUrl!,
                                width: 50,
                                height: 70,
                                fit: BoxFit.cover,
                                placeholder: (c, u) =>
                                    Container(color: Colors.grey[200]),
                                errorWidget: (c, u, e) =>
                                    const Icon(Icons.broken_image),
                              )
                            : Container(
                                color: Colors.grey[200],
                                width: 50,
                                height: 70,
                                child: const Icon(Icons.image),
                              ),
                      ),
                      title: Text(
                        meta.siteUrl ?? meta.siteUrl ?? 'Unbekannter Titel',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: meta.status != null ? Text(meta.status!) : null,
                      onTap: () {
                        Navigator.of(context).pop(meta);
                      },
                    );
                  },
                ),
              )
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Suche nach einem Anime...'),
                ),
              ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                // Return just the text in controller if they want manual entry
                Navigator.of(context).pop(_controller.text.trim());
              },
              child: const Text('Eingegebenen Namen manuell übernehmen'),
            ),
          ],
        ),
      ),
    );
  }
}
