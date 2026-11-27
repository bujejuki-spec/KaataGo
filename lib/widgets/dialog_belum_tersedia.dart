import 'package:flutter/material.dart';

import '../theme.dart';

/// Memberi tahu bahwa sebuah cara bayar belum bisa dipakai.
///
/// ── Kenapa dialog, bukan toast ───────────────────────────────────────
///
/// Toast lewat sendiri dalam dua detik, dan yang baru saja menggeser
/// saklar sedang menatap saklarnya — bukan bagian bawah layar. Ia akan
/// menggesernya lagi, mengira gesernya yang tidak kena.
///
/// Dialog menahan langkahnya sebentar dan menuntut satu ketukan. Untuk
/// hal yang memang tidak bisa dilakukan, itu bentuk yang benar.
///
/// ── Kenapa menyebut apa yang BISA dipakai ────────────────────────────
///
/// "Belum tersedia" saja meninggalkan orangnya di jalan buntu. Yang dia
/// butuhkan berikutnya bukan penjelasan kenapa, melainkan ke mana.
Future<void> dialogBelumTersedia(
  BuildContext context, {
  required String nama,
}) =>
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.info_outline, size: 32, color: Colors.orange),
        title: Text('$nama belum tersedia',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17)),
        content: Text(
          'Silakan gunakan metode pembayaran lainnya.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: KaataTheme.mutedOf(context)),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Mengerti'),
            ),
          ),
        ],
      ),
    );
