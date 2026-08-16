import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/app_prefs_provider.dart';
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
