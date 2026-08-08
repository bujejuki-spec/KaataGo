import 'package:flutter/material.dart';

import '../db/customer_profile_repository.dart';
import '../screens/customer_profile_screen.dart';

/// After a customer's Google login succeeds, call this once — it checks
/// whether they've already filled in their profile (name/phone) before;
/// if not, it shows [CustomerProfileScreen] and waits for them to save.
/// If a profile already exists, this returns immediately (no-op).
Future<void> ensureCustomerProfile(BuildContext context, String email) async {
  final existing = await CustomerProfileRepository().getOnce(email);
  if (existing != null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CustomerProfileScreen(email: email)),
  );
}
