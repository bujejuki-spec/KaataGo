import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import '../widgets/app_toast.dart';

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
  final toast = AppToast.of(context);

  try {
    if (!await Gal.hasAccess()) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        toast.show('Izin galeri ditolak, gambar tidak bisa disimpan.', isError: true);
        return false;
      }
    }

    await Gal.putImageBytes(bytes, album: 'KaataGo');
    toast.show(successMessage);
    return true;
  } catch (e) {
    toast.show('$failurePrefix: $e');
    return false;
  }
}
