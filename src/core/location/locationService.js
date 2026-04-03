/**
 * Aanchal — Location Service
 *
 * Wraps react-native-geolocation-service for live location tracking.
 * Provides current position, continuous watch, and distance utilities.
 */

import Geolocation from 'react-native-geolocation-service';
import { PermissionsAndroid, Platform } from 'react-native';

const TAG = '[LocationService]';

let _watchId = null;
let _lastPosition = null;

const locationService = {
  /**
   * Request Android location permissions.
   * @returns {boolean} granted
   */
  requestPermission: async () => {
    try {
      if (Platform.OS !== 'android') return true;
      const granted = await PermissionsAndroid.request(
        PermissionsAndroid.PERMISSIONS.ACCESS_FINE_LOCATION,
        {
          title: 'Aanchal Location Permission',
          message: 'Aanchal needs your location for safe navigation and SOS.',
          buttonPositive: 'Allow',
        },
      );
      const ok = granted === PermissionsAndroid.RESULTS.GRANTED;
      console.log(TAG, 'Permission', ok ? 'granted' : 'denied');
      return ok;
    } catch (err) {
      console.error(TAG, 'Permission request error', err);
      return false;
    }
  },

  /**
   * Get current position (one‑shot).
   * @returns {{ lat: number, lng: number }}
   */
  getCurrentPosition: () => {
    return new Promise((resolve, reject) => {
      Geolocation.getCurrentPosition(
        (pos) => {
          const coords = {
            lat: pos.coords.latitude,
            lng: pos.coords.longitude,
          };
          _lastPosition = coords;
          console.log(TAG, 'Current position', coords);
          resolve(coords);
        },
        (err) => {
          if (err?.code === 1) {
            console.warn(TAG, 'getCurrentPosition permission denied; using fallback coords');
          } else {
            console.error(TAG, 'getCurrentPosition error', err);
          }
          // Fallback to last known or default
          resolve(_lastPosition || { lat: 0, lng: 0 });
        },
        {
          enableHighAccuracy: true,
          timeout: 15000,
          maximumAge: 10000,
        },
      );
    });
  },

  /**
   * Start continuous location watch.
   * @param {function} onUpdate — receives { lat, lng }
   */
  startWatching: (onUpdate) => {
    if (_watchId !== null) {
      console.warn(TAG, 'Already watching');
      return;
    }

    _watchId = Geolocation.watchPosition(
      (pos) => {
        const coords = {
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
        };
        _lastPosition = coords;
        if (onUpdate) onUpdate(coords);
      },
      (err) => {
        console.error(TAG, 'watchPosition error', err);
      },
      {
        enableHighAccuracy: true,
        distanceFilter: 10,
        interval: 5000,
        fastestInterval: 2000,
      },
    );
    console.log(TAG, 'Watch started', _watchId);
  },

  /**
   * Stop watching location.
   */
  stopWatching: () => {
    if (_watchId !== null) {
      Geolocation.clearWatch(_watchId);
      _watchId = null;
      console.log(TAG, 'Watch stopped');
    }
  },

  /**
   * Get last known position without a fresh GPS call.
   * @returns {{ lat: number, lng: number } | null}
   */
  getLastKnown: () => _lastPosition,

  /**
   * Haversine distance in meters between two { lat, lng } points.
   * @returns {number}
   */
  distanceBetween: (a, b) => {
    const R = 6371e3;
    const toRad = (deg) => (deg * Math.PI) / 180;
    const dLat = toRad(b.lat - a.lat);
    const dLng = toRad(b.lng - a.lng);
    const sinDLat = Math.sin(dLat / 2);
    const sinDLng = Math.sin(dLng / 2);
    const h =
      sinDLat * sinDLat +
      Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinDLng * sinDLng;
    return R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
  },
};

export { locationService };
export default locationService;
