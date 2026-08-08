import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import '../providers/table_session_provider.dart';

/// Lets a customer browse the menu of any registered restaurant without
/// scanning a table QR code first — shown as an alternative to "Scan QR
/// Meja" on the customer landing screen. Picking one starts a session
/// with no table number yet; the table number becomes a mandatory field
/// at checkout instead (see [CustomerCartScreen]).
class RestaurantListScreen extends StatefulWidget {
  const RestaurantListScreen({super.key});

  @override
  State<RestaurantListScreen> createState() => _RestaurantListScreenState();
}

class _RestaurantListScreenState extends State<RestaurantListScreen> {
  final _repo = RestaurantRepository();
  List<Restaurant> _restaurants = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _repo.getAllActive();
    if (!mounted) return;
    setState(() {
      _restaurants = all;
      _loading = false;
    });
  }

  Future<void> _select(Restaurant resto) async {
    await context.read<TableSessionProvider>().setResto(resto.id);
    if (!mounted) return;
    // Same pattern as ScanTableScreen: pop back to CustomerHomeScreen,
    // which is now showing the browsing view underneath.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pilih Resto')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _restaurants.isEmpty
              ? const Center(child: Text('Belum ada resto terdaftar.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _restaurants.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final resto = _restaurants[i];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.storefront_outlined)),
                        title: Text(resto.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          resto.address.isEmpty ? 'Alamat belum diisi' : resto.address,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _select(resto),
                      ),
                    );
                  },
                ),
    );
  }
}
