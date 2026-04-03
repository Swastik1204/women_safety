import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/phone_utils.dart';

class SimInfo {
  final int slotIndex;
  final String displayName;
  final String phoneNumber;
  final bool hasNumber;

  SimInfo({
    required this.slotIndex,
    required this.displayName,
    required this.phoneNumber,
  }) : hasNumber = phoneNumber.isNotEmpty;

  @override
  String toString() => 'SimInfo('
      'slot=$slotIndex, name=$displayName, '
      'number=$phoneNumber)';
}

class SimService {
  static const _channel = MethodChannel('com.aanchal.app/sim');
  static const _kUserPhoneNumber = 'user_phone_number';

  /// Requests READ_PHONE_NUMBERS permission.
  /// Returns true if granted.
  Future<bool> requestPermission() async {
    final status = await Permission.phone.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;

    try {
      final granted = await _channel.invokeMethod<bool>('requestPhonePermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('[SimService] Permission request failed: $e');
      return false;
    }
  }

  /// Returns list of SIMs detected on the device.
  /// Returns empty list if permission denied or API unavailable.
  Future<List<SimInfo>> getSimNumbers() async {
    try {
      final raw = await _channel.invokeMethod<List>('getSimNumbers');
      if (raw == null) return [];
      return raw.map((item) {
        final map = Map<String, String>.from(item as Map);
        return SimInfo(
          slotIndex: int.tryParse(map['slotIndex'] ?? '0') ?? 0,
          displayName: map['displayName'] ?? 'SIM',
          phoneNumber: map['phoneNumber'] ?? '',
        );
      }).toList();
    } catch (e) {
      debugPrint('[SimService] Could not read SIM numbers: $e');
      return [];
    }
  }

  /// Full flow: request permission -> read SIMs -> return list.
  /// Returns empty list if anything fails.
  Future<List<SimInfo>> detectSims() async {
    final granted = await requestPermission();
    if (!granted) {
      debugPrint('[SimService] Phone permission denied');
      return [];
    }
    return getSimNumbers();
  }

  /// Clears stored phone and runs SIM detection again.
  Future<void> resetAndRedetect(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserPhoneNumber);

    final sims = await detectSims();
    if (!context.mounted) return;

    final simsWithNumbers = sims.where((s) => s.hasNumber).toList();
    if (simsWithNumbers.length == 1) {
      final normalized = PhoneUtils.normalize(simsWithNumbers.first.phoneNumber);
      await prefs.setString(_kUserPhoneNumber, normalized);
    }
  }
}
