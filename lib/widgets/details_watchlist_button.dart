import 'package:flutter/material.dart';

class DetailsWatchlistButton extends StatelessWidget {
  final bool isInWatchlist;
  final bool isProcessing;
  final VoidCallback onTap;

  const DetailsWatchlistButton({
    super.key,
    required this.isInWatchlist,
    required this.isProcessing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: Colors.black54,
      radius: 20,
      child: isProcessing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2,
              ),
            )
          : IconButton(
              icon: Icon(
                isInWatchlist ? Icons.favorite : Icons.favorite_border,
                color: isInWatchlist ? Colors.red : Colors.white,
                size: 20,
              ),
              onPressed: onTap,
              padding: EdgeInsets.zero,
            ),
    );
  }
}
