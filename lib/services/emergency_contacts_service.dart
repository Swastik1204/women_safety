// Aanchal — Emergency Contacts Service
//
// Firestore is the primary source for contacts, with SharedPreferences used
// as an offline cache fallback.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logger.dart';
import '../utils/phone_utils.dart';

const _tag = 'EmergencyContactsService';

/// Key used for persisting contacts in SharedPreferences.
const _cacheKey = 'emergency_contacts';

/// Represents a single emergency contact.
class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final String relationship;
  final String createdAt;
  final DateTime addedAt;

  EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.relationship = 'Contact',
    required this.createdAt,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  factory EmergencyContact.fromFirestore(
    String docId,
    Map<String, dynamic> json,
  ) {
    final data = Map<String, dynamic>.from(json);
    data['id'] = (data['id'] as String?)?.trim().isNotEmpty == true
        ? data['id']
        : docId;
    data['createdAt'] =
        (data['createdAt'] as String?) ?? DateTime.now().toIso8601String();
    return EmergencyContact.fromJson(data);
  }

  /// Deserialise from JSON map.
  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      relationship: (json['relationship'] as String?) ?? 'Contact',
      createdAt:
          (json['createdAt'] as String?) ?? DateTime.now().toIso8601String(),
      addedAt: json['addedAt'] != null
          ? (json['addedAt'] is Timestamp
              ? (json['addedAt'] as Timestamp).toDate()
              : DateTime.tryParse(json['addedAt'].toString()) ??
                  DateTime.now())
          : DateTime.now(),
    );
  }

  /// Serialise to JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'relationship': relationship,
        'createdAt': createdAt,
        'addedAt': addedAt.toIso8601String(),
      };

  @override
  String toString() =>
      'EmergencyContact(id=$id, name=$name, phone=$phone, relationship=$relationship)';
}

/// Service for CRUD operations on locally-stored emergency contacts.
class EmergencyContactsService {
  EmergencyContactsService._();
  static final EmergencyContactsService _instance = EmergencyContactsService._();
  factory EmergencyContactsService() => _instance;

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection('users').doc(_uid).collection('emergency_contacts');

  // ─── Public API ───────────────────────────────────────────────────

  /// Stream contacts in real time from Firestore.
  Stream<List<EmergencyContact>> watchContacts() {
    return _ref.orderBy('addedAt', descending: false).snapshots().map((snap) {
      final contacts = snap.docs
          .map((d) => EmergencyContact.fromFirestore(d.id, d.data()))
          .toList();
      unawaited(_cacheContacts(contacts));
      return contacts;
    });
  }

  /// Add a new emergency contact.
  static Future<void> addContact(
    String name,
    String phone,
    String relationship,
  ) async {
    await _instance._addContact(name, phone, relationship);
  }

  /// Retrieve all stored emergency contacts (ordered by creation date).
  static Future<List<EmergencyContact>> getContacts() async {
    return _instance._getContacts();
  }

  /// Remove a contact by its [id]. Returns `true` if removed.
  static Future<bool> removeContact(String id) async {
    return _instance._removeContact(id);
  }

  /// Update an existing contact's name and/or phone by [id].
  static Future<bool> updateContact(
    String id, {
    String? name,
    String? phone,
  }) async {
    return _instance._updateContact(id, name: name, phone: phone);
  }

  /// Clear all stored contacts. Use with caution.
  static Future<void> clearAll() async {
    await _instance._clearAll();
  }

  /// Get the total count of stored contacts.
  static Future<int> count() async {
    final contacts = await getContacts();
    return contacts.length;
  }

  // ─── Internal Firestore + Cache Logic ─────────────────────────────

  Future<void> _addContact(
    String name,
    String phone,
    String relationship,
  ) async {
    final contacts = await _getContacts();
    final safeName = _sanitizeName(name);
    final safePhone = _normalizePhone(phone);

    // Prevent duplicates by phone number.
    final exists = contacts.any((c) => _normalizePhone(c.phone) == safePhone);
    if (exists) {
      logWarn(_tag, 'Contact with phone $safePhone already exists');
      return;
    }

    final id = '${DateTime.now().millisecondsSinceEpoch}'
        '_${DateTime.now().microsecond.toRadixString(36)}';

    final contact = EmergencyContact(
      id: id,
      name: safeName,
      phone: safePhone,
      relationship: relationship.trim().isEmpty ? 'Contact' : relationship.trim(),
      createdAt: DateTime.now().toIso8601String(),
      addedAt: DateTime.now(),
    );

    await _ref.doc(id).set({
      ...contact.toJson(),
      'addedAt': FieldValue.serverTimestamp(),
    });

    await _cacheContacts([...contacts, contact]);
    logInfo(_tag, 'Contact added: $contact');
  }

  Future<List<EmergencyContact>> _getContacts() async {
    try {
      final snap = await _ref.orderBy('addedAt', descending: false).get();
      final contacts = snap.docs
          .map((d) => EmergencyContact.fromFirestore(d.id, d.data()))
          .toList();
      await _cacheContacts(contacts);
      return contacts;
    } catch (e) {
      debugPrint('[Contacts] Firestore offline, using cache: $e');
      return _getCachedContacts();
    }
  }

  Future<bool> _removeContact(String id) async {
    try {
      await _ref.doc(id).delete();

      final cached = await _getCachedContacts();
      cached.removeWhere((c) => c.id == id);
      await _cacheContacts(cached);

      logInfo(_tag, 'Contact removed: $id');
      return true;
    } catch (e) {
      logWarn(_tag, 'Contact not found or delete failed: $id err=$e');
      return false;
    }
  }

  Future<bool> _updateContact(
    String id, {
    String? name,
    String? phone,
  }) async {
    try {
      final doc = await _ref.doc(id).get();
      if (!doc.exists) {
        logWarn(_tag, 'Contact not found for update: $id');
        return false;
      }

      final data = doc.data() ?? <String, dynamic>{};
      final current = EmergencyContact.fromFirestore(id, data);

      final updatedName = name != null ? _sanitizeName(name) : current.name;
      final updatedPhone = phone != null
          ? _normalizePhone(phone)
          : current.phone;

      await _ref.doc(id).set(
        {
          'id': id,
          'name': updatedName,
          'phone': updatedPhone,
          'relationship': current.relationship,
          'createdAt': current.createdAt,
        },
        SetOptions(merge: true),
      );

      final cached = await _getCachedContacts();
      final idx = cached.indexWhere((c) => c.id == id);
      if (idx != -1) {
        cached[idx] = EmergencyContact(
          id: id,
          name: updatedName,
          phone: updatedPhone,
          relationship: current.relationship,
          createdAt: current.createdAt,
          addedAt: current.addedAt,
        );
        await _cacheContacts(cached);
      }

      logInfo(_tag, 'Contact updated: $id');
      return true;
    } catch (e) {
      logWarn(_tag, 'Contact update failed: $id err=$e');
      return false;
    }
  }

  Future<void> _clearAll() async {
    final snap = await _ref.get();
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    await _cacheContacts(const []);
    logInfo(_tag, 'All contacts cleared');
  }

  Future<void> _cacheContacts(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode(contacts.map((c) => c.toJson()).toList()),
    );
  }

  Future<List<EmergencyContact>> _getCachedContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map(
          (j) => EmergencyContact.fromJson(
            Map<String, dynamic>.from(j as Map),
          ),
        )
        .toList();
  }

  static String _sanitizeName(String input) {
    return input.runes
        .where((r) => r <= 0xFFFF || (r >= 0x10000 && r <= 0x10FFFF))
        .map(String.fromCharCode)
        .join()
        .trim();
  }

  static String _normalizePhone(String phone) {
    return PhoneUtils.normalize(phone);
  }
}
