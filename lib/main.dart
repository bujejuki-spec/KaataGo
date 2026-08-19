import 'services/notification_router.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/app_prefs_provider.dart';
import 'services/notification_service.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/category_provider.dart';
import 'providers/level_group_provider.dart';
import 'providers/customer_cart_provider.dart';
import 'providers/product_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/table_session_provider.dart';
import 'screens/root_screen.dart';
import 'widgets/order_notification_binder.dart';
import 'widgets/update_download_banner.dart';
import 'supabase_config.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  await initializeDateFormatting('en_US', null);
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );
  // Notifikasi "pembaruan siap dipasang" harus bisa membuka layar
  // pemasangnya saat diketuk — termasuk kalau aplikasinya baru dibuka
  // lagi sesudah unduhannya selesai di latar. Karena itu pemasangannya
  // di sini, sekali, bukan di layar mana pun.
  NotificationService.instance.onNotificationTap = (payload) {
    if (payload == null || payload.isEmpty) return;
    // Satu kolom payload dipakai dua hal: jalur berkas APK dari
    // pemasang pembaruan, dan nama kejadian dari notifikasi biasa.
    // Awalannya yang membedakan, bukan tebakan dari bentuk isinya.
    if (payload.startsWith('event:')) {
      final isi = payload.substring(6);
      final pisah = isi.indexOf('?');
      if (pisah < 0) {
        NotificationRouter.buka(isi);
        return;
      }
      NotificationRouter.buka(
        isi.substring(0, pisah),
        data: Uri.splitQueryString(isi.substring(pisah + 1)),
      );
      return;
    }
    OpenFilex.open(payload, type: 'application/vnd.android.package-archive');
  };

  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
        ChangeNotifierProvider(create: (_) => LevelGroupProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..load()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CustomerCartProvider()),
        ChangeNotifierProvider(create: (_) => TableSessionProvider()),
        ChangeNotifierProvider(create: (_) => AppPrefsProvider()..load()),
      ],
      // Consumer, bukan langsung MaterialApp: bahasa dan temanya harus
      // bisa berganti tanpa memulai ulang aplikasi — orang yang menekan
      // tombolnya sedang menunggu layarnya berubah saat itu juga.
      child: Consumer<AppPrefsProvider>(
        builder: (context, prefs, _) => MaterialApp(
          // Dipakai notifikasi untuk membuka halaman yang dimaksudnya.
          // Notifikasi tiba di luar pohon widget; tanpa kunci ini tidak
          // ada context yang bisa dipakai bernavigasi dari sana.
          navigatorKey: navigatorKey,
          title: 'KaataGo',
          debugShowCheckedModeBanner: false,
          theme: KaataTheme.light(),
          darkTheme: KaataTheme.dark(),
          themeMode: prefs.themeMode,
          locale: prefs.locale,
          supportedLocales: const [Locale('id'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // Penanda unduhan dipasang di `builder`, bukan membungkus
          // `home`.
          //
          // `home` cuma satu rute. Membungkusnya berarti penandanya ikut
          // tertimbun begitu layar lain dibuka — dan justru di situlah
          // orangnya berada: unduhan 80 MB tidak ditunggui sambil
          // menatap layar hub, dia pindah melihat pesanan masuk atau
          // membuka kasir. Penanda yang hilang persis saat dibutuhkan
          // sama saja dengan tidak ada.
          //
          // `builder` membungkus Navigator-nya, jadi penandanya
          // mengambang di atas rute mana pun yang sedang terbuka.
          builder: (context, child) => UpdateDownloadBanner(
            child: child ?? const SizedBox.shrink(),
          ),
          home: const OrderNotificationBinder(child: RootScreen()),
        ),
      ),
    );
  }
}
