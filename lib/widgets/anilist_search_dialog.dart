import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/anime_metadata.dart';
import '../services/anilist_service.dart';

/// A dialog to manually search and select an anime from AniList.
class AnilistSearchDialog extends StatefulWidget {
  final String initialQuery;

  const AnilistSearchDialog({super.key, required this.initialQuery});

  @override
  State<AnilistSearchDialog> createState() => _AnilistSearchDialogState();
}

class _AnilistSearchDialogState extends State<AnilistSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  final AnilistService _service = AnilistService();
  List<AnimeMetadata> _results = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    if (widget.initialQuery.isNotEmpty) {
      _search();
    }
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _results = [];
    });

    try {
      final results = await _service.searchAnime(query);
      setState(() {
        _results = results;
        _isLoading = false;
        if (results.isEmpty) _error = 'Keine Ergebnisse gefunden';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Fehler bei der Suche';
      });
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
                    'AniList Suche',
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
                labelText: 'Titel oder AniList ID suchen',
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
                        meta.siteUrl ?? 'Unbekannter Titel',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ), // siteUrl often contains the title slug or useful info if null
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (meta.startDate != null)
                            Text('Start: ${meta.startDate!.year}'),
                          if (meta.id != null)
                            Text(
                              'ID: ${meta.id}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
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
          ],
        ),
      ),
    );
  }
}
