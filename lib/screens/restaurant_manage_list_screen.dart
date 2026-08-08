import 'package:flutter/material.dart';

import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import 'restaurant_create_screen.dart';

/// Super Admin's "List Resto" — every registered restaurant, tap one to
/// edit its name/address/category, and a switch to activate/deactivate
/// it. A deactivated resto disappears from the customer's "Pilih Resto"
/// list, and its employees are blocked from logging in (see
/// AuthProvider._checkEmployeeRole). Distinct from the customer-facing
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

  Future<void> _toggleActive(Restaurant resto, bool value) async {
    if (!value) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Nonaktifkan resto?'),
          content: Text(
            '${resto.name} akan hilang dari daftar "Pilih Resto" customer, dan '
            'karyawan resto ini tidak akan bisa login sampai diaktifkan lagi.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Nonaktifkan'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() {
      _restaurants = _restaurants
          .map((r) => r.id == resto.id
              ? Restaurant(id: r.id, name: r.name, address: r.address, category: r.category, active: value)
              : r)
          .toList();
    });
    await _repo.setActive(resto.id, value);
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
                          leading: CircleAvatar(
                            backgroundColor: resto.active ? null : Colors.grey.shade300,
                            child: const Icon(Icons.storefront_outlined),
                          ),
                          title: Text(resto.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            [
                              if (resto.category != null) resto.category!,
                              resto.address.isEmpty ? 'Alamat belum diisi' : resto.address,
                              if (!resto.active) 'Nonaktif',
                            ].join(' • '),
                            style: resto.active ? null : TextStyle(color: Colors.red.shade400),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: resto.active,
                                onChanged: (v) => _toggleActive(resto, v),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(resto),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
