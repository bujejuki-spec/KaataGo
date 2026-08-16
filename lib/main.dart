import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      ],
      child: MaterialApp(
        title: 'KaataGo',
        debugShowCheckedModeBanner: false,
        theme: KaataTheme.light(),
        home: const UpdateDownloadBanner(
          child: OrderNotificationBinder(child: RootScreen()),
        ),
      ),
    );
  }
}
