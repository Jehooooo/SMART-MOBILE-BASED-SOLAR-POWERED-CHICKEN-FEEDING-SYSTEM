import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/feeder_service.dart';
import '../theme/app_theme.dart';

import 'glass_components.dart';

/// Slide-down banner that tells the user when the cloud link to the feeder
/// is lost, reconnecting, or when the cloud database is reachable while the
/// physical ESP32 controller's heartbeat is stale/offline.
///
/// It stays hidden while online and during the first load (skeletons cover
/// that state instead).
class ConnectionBanner extends StatelessWidget {
  final FeederService feederService;

  const ConnectionBanner({super.key, required this.feederService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: feederService,
      builder: (context, _) {
        final state = feederService.connection;
        final deviceOnline = feederService.isDeviceOnline;
        final visible = !feederService.isInitialLoading &&
            (state != FeederConnection.online || !deviceOnline);

        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: visible
                ? _BannerBody(
                    key: ValueKey('${state.name}_$deviceOnline'),
                    state: state,
                    isControllerHeartbeatStale: state == FeederConnection.online && !deviceOnline,
                    lastSyncedAt: feederService.telemetry.lastHeartbeat ?? feederService.lastSyncedAt,
                    errorDetail: feederService.lastErrorMessage,
                    onRetry: () async {
                      if (feederService.isMock) {
                        feederService.setSimulatedOffline(false);
                      }
                      final ok = await feederService.retryConnection();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Reconnected. Live feeder data restored.'
                                  : 'Still offline. Check the feeder\'s Wi-Fi and solar power, then try again.',
                            ),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                    },
                  )
                : const SizedBox(width: double.infinity, key: ValueKey('hidden')),
          ),
        );
      },
    );
  }
}

class _BannerBody extends StatelessWidget {
  final FeederConnection state;
  final bool isControllerHeartbeatStale;
  final DateTime? lastSyncedAt;
  final String? errorDetail;
  final VoidCallback onRetry;

  const _BannerBody({
    super.key,
    required this.state,
    required this.isControllerHeartbeatStale,
    required this.lastSyncedAt,
    required this.errorDetail,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isConnecting = state == FeederConnection.connecting;
    final fg = isConnecting ? c.infoStrong : c.danger;
    final bg = isConnecting ? c.infoSoft : c.dangerSoft;
    final borderColor = isConnecting ? c.infoBorder : c.dangerBorder;

    final lastSeen = lastSyncedAt != null
        ? DateFormat('MMM d, h:mm a').format(lastSyncedAt!)
        : null;

    final String title;
    final String detail;
    if (isConnecting) {
      title = 'Reconnecting to feeder…';
      detail = 'Trying to reach the feeder controller. This usually takes a few seconds.';
    } else if (isControllerHeartbeatStale) {
      title = 'Feeder controller offline';
      detail = 'Cloud database is reachable, but ESP32 has not sent a live heartbeat'
          '${lastSeen != null ? ' since $lastSeen' : ''}. '
          'Manual feeding is paused until the controller reconnects; onboard RTC schedules continue locally.';
    } else {
      title = 'Feeder connection lost';
      detail = (errorDetail != null && errorDetail!.contains('permission denied'))
          ? errorDetail!
          : 'Showing last known data${lastSeen != null ? ' from $lastSeen' : ''}. '
              'Manual feeding is paused until the connection returns. Saved schedules keep running on the feeder.';
    }

    return Semantics(
      liveRegion: true,
      container: true,
      label: '$title. $detail',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: LiquidGlassContainer(
          width: double.infinity,
          borderRadius: BorderRadius.circular(18),
          tintColor: bg,
          tintOpacity: 0.85,
          blurSigma: 16,
          customBorder: Border.all(color: borderColor.withValues(alpha: 0.9), width: 1.2),
          customShadow: [
            BoxShadow(
              color: fg.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isConnecting)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                )
              else
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.cloud_off_rounded, color: fg, size: 20),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(detail, style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: 12, height: 1.3)),
                    ],
                  ),
                ),
              ),
              if (!isConnecting) ...[
                const SizedBox(width: 8),
                LiquidGlassButton(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  backgroundColor: fg.withValues(alpha: 0.18),
                  foregroundColor: fg,
                  glowColor: fg.withValues(alpha: 0.25),
                  onPressed: onRetry,
                  icon: Icon(Icons.refresh_rounded, size: 16, color: fg),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
