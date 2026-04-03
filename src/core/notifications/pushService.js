/**
 * Aanchal — Push Service
 *
 * Firebase Cloud Messaging wrapper.
 * Registers for FCM tokens, sends SOS push notifications,
 * and handles incoming push payloads.
 *
 * Graceful fallback if Firebase is not configured.
 */

const TAG = '[PushService]';

let _fcmToken = null;
let _onMessageCallback = null;
let _unsubscribeOnMessage = null;

const pushService = {
  /**
   * Initialize FCM — request permission and get token.
   */
  init: async () => {
    try {
      const messaging = getMessagingSafe();
      if (!messaging) {
        console.warn(TAG, 'Firebase messaging not available');
        return;
      }

      // Request permission (Android 13+ POST_NOTIFICATIONS; no-op on Android < 13)
      const { requestPermission, getToken, onMessage } = require('@react-native-firebase/messaging');
      const authStatus = await requestPermission(messaging);
      console.log(TAG, 'Auth status', authStatus);

      _fcmToken = await getToken(messaging);
      console.log(TAG, 'FCM token', _fcmToken?.substring(0, 20) + '...');

      // Foreground message handler
      if (_unsubscribeOnMessage) {
        _unsubscribeOnMessage();
      }
      _unsubscribeOnMessage = onMessage(messaging, async (remoteMessage) => {
        console.log(TAG, 'Foreground message', remoteMessage);
        if (_onMessageCallback) {
          _onMessageCallback(remoteMessage);
        }
      });
    } catch (err) {
      console.error(TAG, 'Init failed', err);
    }
  },

  /**
   * Send an SOS push notification via FCM topic.
   * In a real app this would go through your backend;
   * here we just log + simulate.
   *
   * @param {object} payload — SOS payload
   */
  sendSOSPush: async (payload) => {
    console.log(TAG, 'Sending SOS push', payload);
    // Stub: logs and resolves. Real impl would POST to backend → FCM.
    return { sent: true, mock: true };
  },

  /**
   * Register a callback for incoming push messages.
   * @param {function} callback
   */
  onMessage: (callback) => {
    _onMessageCallback = callback;
  },

  /**
   * Get current FCM token.
   * @returns {string|null}
   */
  getToken: () => _fcmToken,
};

function getMessagingSafe() {
  try {
    const { getApps, getApp } = require('@react-native-firebase/app');
    const { getMessaging } = require('@react-native-firebase/messaging');

    const apps = getApps();
    if (!apps || apps.length === 0) {
      console.warn(TAG, 'Firebase app not initialized (missing google-services.json or native config)');
      return null;
    }

    return getMessaging(getApp());
  } catch (err) {
    console.warn(TAG, 'Firebase messaging module not available', err?.message || String(err));
    return null;
  }
}

export { pushService };
export default pushService;
