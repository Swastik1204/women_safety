// Aanchal — App Entry Point
//
// MaterialApp with Riverpod, auth gate, bottom navigation,
// Firebase init, FCM wiring, WorkManager background sync,
// and Watch connectivity.

import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'features/auth/auth_screen.dart';
import 'features/community/community_screen.dart';
import 'features/community/restricted_community_screen.dart';
import 'features/community/missed_calls_screen.dart';
import 'features/home/home_screen.dart';
import 'features/sos/sos_screen.dart';
import 'features/map/map_screen.dart';
import 'features/learning/learning_screen.dart';
import 'features/profile/profile_screen.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/firebase_sync_service.dart';
import 'core/app_config.dart';
import 'core/backend_wake_ui.dart';
import 'core/logger.dart';
import 'ui/app_theme.dart';
import 'services/presence_service.dart';
import 'services/sos_service.dart';
import 'services/watch_connectivity_service.dart';
import 'calling/signaling_service.dart';
import 'calling/call_state_manager.dart';
import 'calling/call_notification.dart';
import 'calling/incoming_call_screen.dart';
import 'services/fcm_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// WorkManager background task name.
const _firebaseSyncTask = 'com.aanchal.firebaseSync';

/// Top-level callback for WorkManager (must be a top-level function).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == _firebaseSyncTask) {
      return await FirebaseSyncService.backgroundSyncCallback();
    }
    return true;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Firebase SDK.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Enable Firebase App Check to avoid placeholder-token warnings and tighten
  // request integrity checks.
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode
          ? AppleProvider.debug
          : AppleProvider.appAttestWithDeviceCheckFallback,
    );
  } catch (e) {
    logWarn('Main', 'Firebase App Check activation failed: $e');
  }

  // Initialise WorkManager for background Firebase sync.
  await Workmanager().initialize(callbackDispatcher);

  // Register FCM background message handler.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Register periodic sync task (every 12 hours).
  await Workmanager().registerPeriodicTask(
    'aanchal-firebase-sync',
    _firebaseSyncTask,
    frequency: Duration(hours: AppConfig.firebaseSyncIntervalHours),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
    initialDelay: const Duration(minutes: 5),
  );

  // Initialise Firebase sync service (generates device ID if needed).
  await FirebaseSyncService.initialise();

  logInfo('Main', 'Aanchal app starting...');

  runApp(const ProviderScope(child: AanchalApp()));
}

class AanchalApp extends StatelessWidget {
  const AanchalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aanchal',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: BackendWakeUi.scaffoldMessengerKey,
      navigatorKey: navigatorKey,
      theme: AppTheme.dark(),
      home: const _AuthGate(),
    );
  }
}

// ─── Auth Gate ────────────────────────────────────────────────────────────────

/// Shows [AuthScreen] when the user has no active session, otherwise shows
/// [MainShell] directly. Checks the locally cached profile first so returning
/// users never see a flash of the auth screen.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _checking = true;
  bool _authenticated = false;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    // Fast path: check Firebase Auth session + cached profile.
    if (AuthService.isSignedIn) {
      final cached = await AuthService.getCachedProfile();
      if (cached != null) {
        setState(() {
          _profile = cached;
          _authenticated = true;
          _checking = false;
        });
        return;
      }

      final uid = AuthService.currentUser?.uid;
      if (uid != null) {
        final remoteProfile = await AuthService.getProfileFromFirestore(uid);
        if (remoteProfile != null) {
          setState(() {
            _profile = remoteProfile;
            _authenticated = true;
            _checking = false;
          });
          return;
        }
      }
    }
    setState(() => _checking = false);
  }

  void _onAuthSuccess(UserProfile profile) {
    setState(() {
      _profile = profile;
      _authenticated = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_authenticated) {
      return MainShell(profile: _profile!);
    }
    return AuthScreen(onAuthSuccess: _onAuthSuccess);
  }
}

/// Bottom-navigation shell hosting the primary screens.
class MainShell extends StatefulWidget {
  final UserProfile profile;
  const MainShell({super.key, required this.profile});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _kUserPhoneNumber = 'user_phone_number';

  int _index = 0;
  bool _fcmInitialized = false;
  late UserProfile _profile;
  StreamSubscription<DocumentSnapshot>? _profileSub;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;

    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(_profile.uid)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted || !snap.exists) return;
            final updated = UserProfile.fromMap(snap.data()!);
            setState(() => _profile = updated);
          },
          onError: (e) {
            logWarn('Main', 'Profile stream update failed: $e');
          },
        );

    PresenceService.instance.start(widget.profile.uid);
    SOSService.instance.initListen(widget.profile.uid);

    // Defer heavy startup work until first frame is painted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initCalling());
      unawaited(_initWatchConnectivity());
      unawaited(_showPhoneCaptureIfNeeded());
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    PresenceService.instance.stop();
    FcmService.instance.dispose();
    CallStateManager.instance.dispose();
    SOSService.instance.dispose();
    SignalingService.instance.disconnect();
    WatchConnectivityService.instance.dispose();
    super.dispose();
  }

  /// Initialise Apple Watch connectivity — listens for SOS triggers.
  Future<void> _initWatchConnectivity() async {
    try {
      final watchService = WatchConnectivityService.instance;
      await watchService.init();
      await watchService.syncUserToWatch(widget.profile);

      // When the Watch triggers SOS, navigate the phone UI to the SOS tab.
      watchService.onSOSTriggeredFromWatch = () {
        if (mounted) {
          setState(() => _index = 1); // SOS is tab index 1
        }
      };
    } catch (e) {
      logWarn('Main', 'Watch connectivity init skipped: $e');
    }
  }

  /// Connect to the signaling server and set up the incoming-call overlay.
  Future<void> _initCalling() async {
    try {
      // 1. Initialize CallKit notification listeners.
      CallNotificationService.instance.init();

      // 2. Connect to signaling server.
      await SignalingService.instance.connect(widget.profile.uid);

      // 3. Initialize call state manager.
      CallStateManager.instance.init(
        widget.profile.uid,
        displayName: '${widget.profile.firstName} ${widget.profile.lastName}',
      );

      // 3b. Initialize FCM (token registration + message listeners).
      await FcmService.instance.initForUser(widget.profile.uid);
      _fcmInitialized = true;

      // 4. Handle incoming calls — show call screen.
      CallStateManager.instance.onIncomingCall = (callData) {
        if (!mounted) return;
        // Show native notification.
        CallNotificationService.instance.showIncomingCall(
          callId: callData.callId,
          callerName: callData.callerName,
        );
        // Push call screen.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => IncomingCallScreen(
                currentUser: widget.profile,
                incomingCall: callData,
              ),
            ),
          );
        });
      };

      // 5. Handle accept from CallKit notification.
      CallNotificationService.instance.onAccept = (callId) {
        CallStateManager.instance.acceptCall(callId);
      };

      // 6. Handle reject from CallKit notification.
      CallNotificationService.instance.onReject = (callId) {
        CallStateManager.instance.rejectCall(callId);
      };
    } catch (e, st) {
      logError('Main', 'Calling bootstrap failed: $e', st);
    }
  }

  Future<void> _showPhoneCaptureIfNeeded() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolvePhoneOnStartup();
    });
  }

  Future<void> _resolvePhoneOnStartup() async {
    if (!mounted) return;

    final phone = await FcmService.instance.ensureUserPhone();
    if (!mounted) return;

    if (phone != null && phone.isNotEmpty) {
      if (_fcmInitialized) {
        await FcmService.instance.registerToken(reason: 'sim_detected');
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kUserPhoneNumber);
    final hasPhone = stored != null && stored.trim().isNotEmpty;
    if (hasPhone || !mounted) return;

    await _showManualPhoneDialog();
  }

  Future<void> _showManualPhoneDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PhoneCaptureDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool isFemale = (_profile.gender ?? '').toLowerCase() == 'female';
    final bool canAccessCommunity = _profile.isAadhaarVerified && isFemale;
    final screens = [
      HomeScreen(currentUser: _profile),
      SOSScreen(currentUser: _profile),
      const MapScreen(),
      canAccessCommunity
          ? CommunityScreen(currentUser: _profile)
          : const RestrictedCommunityScreen(),
      const LearningScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aanchal'),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            // ── Profile header ──────────────────────────────────────────
            UserAccountsDrawerHeader(
              accountName: Text(
                '${_profile.firstName} ${_profile.lastName}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              accountEmail: Text(_profile.email),
              currentAccountPicture: GestureDetector(
                onTap: () async {
                  Navigator.pop(context); // close drawer
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(currentUser: _profile),
                    ),
                  );
                  // Refresh profile in case it was updated (e.g. photo changed)
                  final updated = await AuthService.getCachedProfile();
                  if (updated != null && mounted) {
                    setState(() {
                      _profile = updated;
                    });
                  }
                },
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage: _profile.photoUrl != null
                      ? NetworkImage(_profile.photoUrl!)
                      : null,
                  child: _profile.photoUrl == null
                      ? Icon(
                          Icons.person,
                          size: 40,
                          color: Theme.of(context).primaryColor,
                        )
                      : null,
                ),
              ),
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            ),

            // ── Navigation items ────────────────────────────────────────
            _DrawerItem(
              icon: Icons.home,
              label: 'Home',
              selected: _index == 0,
              onTap: () => _selectTab(context, 0),
            ),
            _DrawerItem(
              icon: Icons.emergency,
              label: 'SOS',
              selected: _index == 1,
              onTap: () => _selectTab(context, 1),
            ),
            _DrawerItem(
              icon: Icons.map,
              label: 'Map',
              selected: _index == 2,
              onTap: () => _selectTab(context, 2),
            ),
            _DrawerItem(
              icon: Icons.people,
              label: 'Community',
              selected: _index == 3,
              onTap: () => _selectTab(context, 3),
            ),
            _DrawerItem(
              icon: Icons.school,
              label: 'Learn',
              selected: _index == 4,
              onTap: () => _selectTab(context, 4),
            ),
            _DrawerItem(
              icon: Icons.call_missed,
              label: 'Missed Calls',
              selected: false,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MissedCallsScreen(currentUser: _profile),
                  ),
                );
              },
            ),

            const Spacer(),

            // ── Logout ──────────────────────────────────────────────────
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: scheme.error),
              title: Text('Logout', style: TextStyle(color: scheme.error)),
              onTap: () async {
                PresenceService.instance.stop();
                await FcmService.instance.dispose();
                CallStateManager.instance.dispose();
                SignalingService.instance.disconnect();
                await AuthService.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const _AuthGate()),
                    (_) => false,
                  );
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.emergency_outlined),
            selectedIcon: Icon(Icons.emergency),
            label: 'SOS',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Community',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Learn',
          ),
        ],
      ),
    );
  }

  void _selectTab(BuildContext context, int index) {
    setState(() => _index = index);
    Navigator.pop(context); // close the drawer
  }
}

/// Single row in the navigation drawer.
class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? scheme.primary : scheme.onSurface,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: selected,
      onTap: onTap,
    );
  }
}

class _PhoneCaptureDialog extends StatefulWidget {
  const _PhoneCaptureDialog();

  @override
  State<_PhoneCaptureDialog> createState() => _PhoneCaptureDialogState();
}

class _PhoneCaptureDialogState extends State<_PhoneCaptureDialog> {
  static const _kUserPhoneNumber = 'user_phone_number';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Phone number is required';

    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) return null;
    if (digits.length == 12 && digits.startsWith('91')) return null;
    return 'Enter a valid Indian number (e.g. +91XXXXXXXXXX)';
  }

  String _normalizePhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return '+$digits';
    }
    return '+91${digits.substring(digits.length - 10)}';
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final normalizedPhone = _normalizePhone(_phoneController.text.trim());

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUserPhoneNumber, normalizedPhone);
      await FcmService.instance.registerToken(reason: 'phone_saved');
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your Phone Number'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('So your emergency contacts can find you in the app'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: '+91XXXXXXXXXX',
                border: OutlineInputBorder(),
              ),
              validator: _validatePhone,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
