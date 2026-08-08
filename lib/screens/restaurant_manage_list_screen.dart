import 'package:flutter/material.dart';

import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import 'restaurant_create_screen.dart';

/// Super Admin's "List Resto" — every registered restaurant, tap one to
/// edit its name/address/category. Distinct from the customer-facing
/// [RestaurantListScreen] (browse-to-order, no edit capability).
class RestaurantManageListScreen extends StatefulWidget {
  const RestaurantManageListScreen({super.key});

  @override
  State<RestaurantManageListScreen> createState() => _RestaurantManageListScreenState();
}

class _RestaurantManageListScreenState extends State<RestaurantManageListScreen> {
  final _repo = RestaurantRepository();
  List<Restaurant> _restaurants = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await _repo.getAll();
    if (!mounted) return;
    setState(() {
      _restaurants = all;
      _loading = false;
    });
  }

  Future<void> _edit(Restaurant resto) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RestaurantCreateScreen(existing: resto)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('List Resto')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RestaurantCreateScreen()),
          );
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Resto Baru'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _restaurants.isEmpty
              ? const Center(child: Text('Belum ada resto terdaftar.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
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
                            [
                              if (resto.category != null) resto.category!,
                              resto.address.isEmpty ? 'Alamat belum diisi' : resto.address,
                            ].join(' • '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _edit(resto),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
