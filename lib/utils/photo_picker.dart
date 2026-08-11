import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Asks where the photo should come from, then returns it.
///
/// Both places that attach proof to a money movement — nota pengeluaran
/// and bukti setoran — want exactly this: camera first because the paper
/// is usually right there, gallery for a transfer receipt already saved
/// on the phone.
///
/// Sized at 900px/70%: big enough that printed numbers stay readable,
/// small enough that the base64 blob doesn't bloat the row it's stored
/// in. Product photos use the same approach at a smaller size, since
/// those never need to be legible as text.
///
/// Returns null when the sheet is dismissed, the picker is cancelled, or
/// camera permission is refused — every one of those is the user saying
/// "not now", so the caller just carries on without a photo.
Future<File?> pickProofPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Ambil Foto'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Pilih dari Galeri'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;

  // mobile_scanner declares android.permission.CAMERA, which makes
  // Android refuse the capture intent outright unless it's been granted
  // — and image_picker never asks for it. Finance and Kasir have no
  // reason to have opened the QR scanner that would have.
  if (source == ImageSource.camera) {
    final status = await Permission.camera.request();
    if (!context.mounted) return null;
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Izin kamera ditolak. Pakai galeri, atau aktifkan lewat Pengaturan.'),
          action: status.isPermanentlyDenied
              ? const SnackBarAction(label: 'Pengaturan', onPressed: openAppSettings)
              : null,
        ),
      );
      return null;
    }
  }

  try {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 900,
      imageQuality: 70,
    );
    return picked == null ? null : File(picked.path);
  } catch (e) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Gagal mengambil gambar: $e')),
    );
    return null;
  }
}
