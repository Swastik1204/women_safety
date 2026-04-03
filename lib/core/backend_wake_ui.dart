import 'package:flutter/material.dart';

class BackendWakeUi {
  BackendWakeUi._();

  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  static bool _bannerVisible = false;

  /// Shows a non-blocking banner with progress while backend wake-up is in-flight.
  static void showConnectingBanner() {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null || _bannerVisible) return;

    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.cloud_sync),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connecting to server, please wait...'),
            SizedBox(height: 10),
            LinearProgressIndicator(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: hideConnectingBanner,
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
    _bannerVisible = true;
  }

  static void hideConnectingBanner() {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentMaterialBanner();
    _bannerVisible = false;
  }

  static void showUnavailableMessage() {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger.hideCurrentMaterialBanner();
    _bannerVisible = false;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Server unavailable. Try again in a moment.'),
      ),
    );
  }
}
