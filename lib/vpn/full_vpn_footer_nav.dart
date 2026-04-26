import 'package:flutter/material.dart';

class FullVpnFooterNav extends StatelessWidget {
  final String active;
  final Function(String) onTabChange;

  const FullVpnFooterNav({
    super.key,
    required this.active,
    required this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0B1626).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: const Color(0xFF22304A).withValues(alpha: 0.70),
                width: 1.0,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: IntrinsicHeight(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildItem(context, Icons.vpn_key_outlined, "Connection", "connection"),
                  _divider(),
                  _buildItem(context, Icons.dns_outlined, "DNS", "dns"),
                  _divider(),
                  _buildItem(context, Icons.shield_outlined, "S.H.I.E.L.D", "customisation"),
                  _divider(),
                  _buildItem(context, Icons.settings_outlined, "Settings", "settings"),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1.0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: const Color(0xFF22304A).withValues(alpha: 0.65),
    );
  }

  Widget _buildItem(
      BuildContext context,
      IconData icon,
      String title,
      String tag,
      ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

    final isActive = active == tag;

    final activeColor = scheme.primary;
    final inactiveColor = scheme.onSurfaceVariant;
    final color = isActive ? activeColor : inactiveColor;

    return Expanded(
      child: InkWell(
        onTap: () => onTabChange(tag),
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isActive
                      ? scheme.primary.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  border: isActive
                      ? Border.all(
                    color: scheme.primary.withValues(alpha: 0.22),
                    width: 1.0,
                  )
                      : null,
                ),
                child: Icon(
                  icon,
                  color: isActive ? scheme.primary : inactiveColor,
                  size: 22,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: text.labelSmall?.copyWith(
                  color: color,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.1,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}