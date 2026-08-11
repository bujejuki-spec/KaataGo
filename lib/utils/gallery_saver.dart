import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

/// Drops [bytes] (a PNG) into the device's photo gallery, under a
/// "KaataGo" album, handling the permission prompt Android 9 and below
/// still need.
///
/// Returns true only if the image actually landed. Failures — including
/// a refused permission — are reported through [context] rather than
/// thrown, since every caller here is a "save this for me" button where
/// a snackbar is the whole error handling anyone wants.
Future<bool> savePngToGallery(
  BuildContext context,
  Uint8List bytes, {
  required String successMessage,
  String failurePrefix = 'Gagal menyimpan',
}) async {
  final messenger = ScaffoldMessenger.of(context);

  try {
    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Izin galeri ditolak, gambar tidak bisa disimpan.')),
        );
        return false;
      }
    }

    await Gal.putImageBytes(bytes, album: 'KaataGo');
    messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$failurePrefix: $e')));
    return false;
  }
}
