import 'dart:async';
import 'package:colourswift_av/vpn/services/full_vpn_location_map.dart';
import 'package:flutter/material.dart';
import 'package:colourswift_av/vpn/services/full_vpn_backend.dart';

class FullVpnDemoHomeScreen extends StatefulWidget {
  const FullVpnDemoHomeScreen({super.key});

  @override
  State<FullVpnDemoHomeScreen> createState() => _FullVpnDemoHomeScreenState();
}

class _FullVpnDemoHomeScreenState extends State<FullVpnDemoHomeScreen>
    with WidgetsBindingObserver {
  late final FullVpnController c;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    c = FullVpnController(
      apiBase: "https://api.colourswift.com",
      loginUrl: "https://api.colourswift.com/login",
      deepLinkPrefix: "colourswift://auth?token=",
    );

    c.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.onResumed();
    }
  }

  Future<void> _pickServer() async {
    final picked = await showModalBottomSheet<FullVpnServerLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
              ),
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                itemCount: c.servers.length,
                itemBuilder: (_, i) {
                  final s = c.servers[i];
                  final selected = s.id == c.selectedServerId;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primary.withOpacity(0.12)
                          : scheme.surfaceContainerHighest.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? scheme.primary.withOpacity(0.85)
                            : scheme.outlineVariant.withOpacity(0.35),
                      ),
                    ),
                    child: ListTile(
                      title: Text(
                        s.label,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(
                        "${s.countryCode}  •  ${s.id}",
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: selected
                          ? Icon(Icons.check_rounded, color: scheme.primary)
                          : null,
                      onTap: () => Navigator.pop(ctx, s),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );

    if (picked == null) return;
    c.selectServerPreview(picked);
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final scheme = base.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("VPN Demo"),
        actions: [
          IconButton(
            onPressed: _pickServer,
            icon: const Icon(Icons.public),
            tooltip: "Servers",
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          final s = c.selectedServer;

          final stateText = c.connectingUi
              ? "Connecting"
              : (c.connected ? "Connected" : "Disconnected");

          final canConnect =
              !c.connected && !c.busy && !c.softCapReached && !c.connectingUi;
          final canDisconnect = c.connected && !c.busy;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stateText,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        c.status.isNotEmpty ? c.status : "Ready",
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: scheme.surface.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Server",
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${s.label} (${s.countryCode})",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: c.busy ? null : _pickServer,
                            child: const Text("Change"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: canConnect ? () async => c.connect() : null,
                              child: Text(c.connectingUi ? "Connecting..." : "Connect"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: canDisconnect ? () async => c.disconnect() : null,
                              child: const Text("Disconnect"),
                            ),
                          ),
                        ],
                      ),
                      if (c.softCapReached) ...[
                        const SizedBox(height: 10),
                        Text(
                          "Free monthly limit reached.",
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Debug",
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(height: 10),
                        _kv("busy", c.busy.toString()),
                        _kv("connectingUi", c.connectingUi.toString()),
                        _kv("connected", c.connected.toString()),
                        _kv("token", c.token.isNotEmpty ? "present" : "missing"),
                        _kv("selectedServerId", c.selectedServerId),
                        _kv("uiCountry", c.uiCountry.isEmpty ? "-" : c.uiCountry),
                        _kv("uiCity", c.uiCity.isEmpty ? "-" : c.uiCity),
                        _kv("uiIp", c.uiIp.isEmpty ? "-" : c.uiIp),
                        const SizedBox(height: 10),
                        Text(
                          c.status.isEmpty ? "-" : c.status,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              k,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}