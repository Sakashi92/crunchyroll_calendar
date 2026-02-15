import 'package:flutter/material.dart';
import '../services/app_settings_service.dart';
import '../utils/ui_utils.dart';

class HiddenAnimePage extends StatefulWidget {
  const HiddenAnimePage({super.key});

  @override
  State<HiddenAnimePage> createState() => _HiddenAnimePageState();
}

class _HiddenAnimePageState extends State<HiddenAnimePage> {
  List<String> _hiddenAnime = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHiddenAnime();
  }

  Future<void> _loadHiddenAnime() async {
    final list = await AppSettingsService.getHiddenAnime();
    if (mounted) {
      setState(() {
        _hiddenAnime = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _unhide(String title) async {
    await AppSettingsService.unhideAnime(title);
    await _loadHiddenAnime();
    if (mounted) {
      UIUtils.showSnackBar(
        context,
        SnackBar(
          content: Text('"$title" wieder eingeblendet'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Versteckte Anime')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hiddenAnime.isEmpty
          ? const Center(
              child: Text(
                'Keine versteckten Anime.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: _hiddenAnime.length,
              itemBuilder: (context, index) {
                final title = _hiddenAnime[index];
                return ListTile(
                  title: Text(title),
                  trailing: IconButton(
                    icon: const Icon(Icons.visibility),
                    tooltip: 'Wieder anzeigen',
                    onPressed: () => _unhide(title),
                  ),
                );
              },
            ),
    );
  }
}
