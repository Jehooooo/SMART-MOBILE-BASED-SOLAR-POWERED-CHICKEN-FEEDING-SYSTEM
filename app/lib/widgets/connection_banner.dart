import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/feeder_service.dart';
import '../theme/app_theme.dart';

/// Slide-down banner that tells the user when the cloud link to the feeder
/// is lost or reconnecting (Nielsen #1: Visibility of system status, and
/// #9: Help users recognize, diagnose, and recover from errors).
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
        final visible = !feederService.isInitialLoading && state != FeederConnection.online;

        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: visible
                ? _BannerBody(
                    key: ValueKey(state),
                    state: state,
                    lastSyncedAt: feederService.lastSyncedAt,
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
  final DateTime? lastSyncedAt;
  final VoidCallback onRetry;

  const _BannerBody({super.key, required this.state, required this.lastSyncedAt, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isConnecting = state == FeederConnection.connecting;
    final fg = isConnecting ? c.infoStrong : c.danger;
    final bg = isConnecting ? c.infoSoft : c.dangerSoft;
    final borderColor = isConnecting ? c.infoBorder : c.dangerBorder;

    final lastSeen = lastSyncedAt != null ? DateFormat('h:mm a').format(lastSyncedAt!) : null;
    final title = isConnecting ? 'Reconnecting to feeder…' : 'Feeder connection lost';
    final detail = isConnecting
        ? 'Trying to reach the cloud database. This usually takes a few seconds.'
        : 'Showing last known data${lastSeen != null ? ' from $lastSeen' : ''}. '
            'Manual feeding is paused until the connection returns. Saved schedules keep running on the feeder.';

    return Semantics(
      liveRegion: true,
      container: true,
      label: '$title. $detail',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: fg.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
              TextButton.icon(
                onPressed: onRetry,
                icon: Icon(Icons.refresh_rounded, size: 18, color: fg),
                label: Text('Retry', style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
