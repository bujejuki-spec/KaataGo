import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/app_toast.dart';

/// Menghubungi merchant lewat WhatsApp atau surel.
///
/// Dipakai KaataGo Admin dari List Merchant dan dari tagihan langganan.

/// Nomor Indonesia jadi bentuk yang dimengerti wa.me.
///
/// wa.me menuntut nomor internasional tanpa tanda plus, tanpa spasi,
/// tanpa tanda hubung. Yang diketik orang bermacam-macam: `0813-1609
/// 0867`, `+62 813...`, `62813...`. Yang tidak dinormalkan menghasilkan
/// tautan yang terbuka lalu berhenti di layar "nomor tidak valid" —
/// kegagalan yang terlihat seperti WhatsApp-nya yang bermasalah, bukan
/// nomornya.
///
/// Mengembalikan null kalau tidak ada angka yang tersisa; pemanggilnya
/// yang memutuskan artinya.
String? nomorWhatsApp(String? mentah) {
  if (mentah == null) return null;
  var angka = mentah.replaceAll(RegExp(r'[^0-9+]'), '');
  if (angka.startsWith('+')) angka = angka.substring(1);
  if (angka.startsWith('0')) angka = '62${angka.substring(1)}';
  // Nomor lokal yang ditulis tanpa nol di depan — 813..., 21... — tetap
  // perlu kode negaranya.
  if (!angka.startsWith('62')) angka = '62$angka';
  // Kode negara saja bukan nomor.
  if (angka.length <= 4) return null;
  return angka;
}

/// Ada nomor yang benar-benar bisa dihubungi.
bool punyaWhatsApp(String? phone) =>
    phone != null && phone.trim().isNotEmpty && nomorWhatsApp(phone) != null;

bool punyaSurel(String? email) =>
    email != null && email.trim().isNotEmpty && email.contains('@');

/// Membuka percakapan WhatsApp dengan sebuah nomor.
Future<void> bukaWhatsApp(
  BuildContext context,
  String? phone, {
  String? pesan,
}) async {
  final nomor = nomorWhatsApp(phone);
  if (nomor == null) {
    if (context.mounted) {
      showAppToast(context, 'Nomor WhatsApp-nya tidak terbaca.', isError: true);
    }
    return;
  }

  final url = Uri.parse(
      'https://wa.me/$nomor${pesan == null ? '' : '?text=${Uri.encodeComponent(pesan)}'}');
  await _buka(context, url, 'Tidak bisa membuka WhatsApp.');
}

/// Membuka aplikasi surel dengan subjek dan isi yang sudah terisi.
Future<void> bukaSurel(
  BuildContext context,
  String? email, {
  String? subjek,
  String? isi,
}) async {
  if (!punyaSurel(email)) {
    if (context.mounted) {
      showAppToast(context, 'Alamat surelnya belum diisi.', isError: true);
    }
    return;
  }

  // Query disusun lewat Uri, bukan dirangkai sendiri: subjek dan isi
  // berisi spasi, baris baru, dan tanda baca yang harus dikodekan — dan
  // yang dirangkai tangan hampir selalu benar sampai ada satu tanda
  // tanya di dalam nominalnya.
  final url = Uri(
    scheme: 'mailto',
    path: email!.trim(),
    query: Uri(queryParameters: {
      if (subjek != null) 'subject': subjek,
      if (isi != null) 'body': isi,
    }).query,
  );
  await _buka(context, url, 'Tidak ada aplikasi surel yang terpasang.');
}

Future<void> _buka(BuildContext context, Uri url, String pesanGagal) async {
  // Di web, LaunchMode.externalApplication berarti window.open — dan
  // jendela yang dibuka bukan karena ketukan langsung diblokir peramban,
  // menyisakan tab kosong tanpa penjelasan. `_self` menyerahkannya ke
  // penanganan tautan bawaan, yang di HP membuka aplikasinya.
  final ok = kIsWeb
      ? await launchUrl(url, webOnlyWindowName: '_self')
      : await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showAppToast(context, pesanGagal, isError: true);
  }
}
