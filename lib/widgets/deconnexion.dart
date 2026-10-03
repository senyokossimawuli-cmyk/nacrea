import 'package:flutter/material.dart';

import '../data/base_locale.dart';

/// Se déconnecter, sauf si des ventes attendent encore d'être envoyées au serveur.
Future<void> deconnexion(BuildContext context) async {
  final refus = await seDeconnecter();
  if (refus != null && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Pas encore'),
        content: Text(refus),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Compris')),
        ],
      ),
    );
  }
}
