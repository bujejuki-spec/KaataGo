import 'package:flutter/material.dart';

/// A colorful menu row used on "hub" home screens (Super Admin, Finance)
/// — an icon in a soft gradient badge, title/subtitle, and a chevron.
/// Nicer than a plain ListTile-in-a-Card, and each entry can carry its
/// own accent color so the menu doesn't read as one flat block.
class HubMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const HubMenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, Color.lerp(color, Colors.black, 0.18)!],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

/// A soft gradient hero header used at the top of hub home screens —
/// shows the app mark, a role label ("Finance" / "Super Admin"), and an
/// optional detail line (e.g. the logged-in email).
class HubHeader extends StatelessWidget {
  final Widget logo;
  final String roleLabel;
  final String? detail;
  final Color colorA;
  final Color colorB;

  const HubHeader({
    super.key,
    required this.logo,
    required this.roleLabel,
    required this.colorA,
    required this.colorB,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorA, colorB],
        ),
      ),
      child: Column(
        children: [
          logo,
          const SizedBox(height: 14),
          Text(
            roleLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}
