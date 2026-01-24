import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class DetailsHeaderImage extends StatelessWidget {
  final String? imageUrl;
  final bool isPremiere;
  final bool isPredicted;
  final Widget? watchlistButton;
  final VoidCallback onClose;

  const DetailsHeaderImage({
    super.key,
    this.imageUrl,
    this.isPremiere = false,
    this.isPredicted = false,
    this.watchlistButton,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (imageUrl != null && imageUrl!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: imageUrl!,
            height: 220,
            width: double.infinity,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              height: 220,
              color: Colors.grey.shade300,
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) =>
                Container(height: 220, color: Colors.grey.shade300),
          )
        else
          Container(height: 220, color: Colors.grey.shade300),

        if (watchlistButton != null)
          Positioned(top: 8, left: 8, child: watchlistButton!),

        Positioned(
          top: 8,
          right: 8,
          child: CircleAvatar(
            backgroundColor: Colors.black54,
            radius: 18,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              onPressed: onClose,
              padding: EdgeInsets.zero,
            ),
          ),
        ),

        if (isPremiere)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'PREMIERE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),

        if (isPredicted)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Vorhersage',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
