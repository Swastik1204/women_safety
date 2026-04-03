// Aanchal — Auth Service
//
// Wraps Firebase Auth + Firestore for registration and login.
// On success, the user profile is cached locally in SharedPreferences
// so the app can show the profile instantly without a network round-trip.

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logger.dart';
import 'ble_service.dart';
import 'sos_listener_service.dart';
import 'voice_trigger_service.dart';

const _tag = 'AuthService';

//  Model 

class UserProfile {
  final String uid;
  final String firstName;
  final String lastName;
  final String? dob;
  final String email;
  final String aanchalNumber;
  final String? photoUrl;
  final String? aadhaarNumber;
  final bool isAadhaarVerified;
  final String? gender;

  UserProfile({
    required this.uid,
    String? firstName,
    String? lastName,
    String? name,
    this.dob,
    required this.email,
    required this.aanchalNumber,
    this.photoUrl,
    this.aadhaarNumber,
    this.isAadhaarVerified = false,
    this.gender,
  })  : firstName = _resolveFirstName(firstName, name),
        lastName = _resolveLastName(lastName, name);

  static String _resolveFirstName(String? firstName, String? name) {
    final f = (firstName ?? '').trim();
    if (f.isNotEmpty) return f;

    final parts = _splitName(name ?? '');
    return parts.first;
  }

  static String _resolveLastName(String? lastName, String? name) {
    final l = (lastName ?? '').trim();
    if (l.isNotEmpty) return l;

    final parts = _splitName(name ?? '');
    return parts.length > 1 ? parts.sublist(1).join(' ') : 'User';
  }

  static List<String> _splitName(String raw) {
    final compact = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) return ['Aanchal', 'User'];
    return compact.split(' ');
  }

  // Backward-compatible full name getter used across existing screens.
  String get name {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? 'Aanchal User' : full;
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    String fName = (map['firstName'] as String?)?.trim() ?? '';
    String lName = (map['lastName'] as String?)?.trim() ?? '';

    if (fName.isEmpty && lName.isEmpty) {
      final legacyName = (map['name'] as String?)?.trim() ?? '';
      final parts = _splitName(legacyName);
      fName = parts.first;
      lName = parts.length > 1 ? parts.sublist(1).join(' ') : 'User';
    }

    return UserProfile(
      uid: (map['uid'] as String?) ?? '',
      firstName: fName,
      lastName: lName,
      dob: map['dob'] as String?,
      email: (map['email'] as String?) ?? '',
      aanchalNumber: (map['aanchalNumber'] as String?) ?? '',
      photoUrl: map['photoUrl'] as String?,
      aadhaarNumber: map['aadhaarNumber'] as String?,
      isAadhaarVerified: (map['isAadhaarVerified'] as bool?) ?? false,
      gender: map['gender'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'firstName': firstName,
    'lastName': lastName,
    'name': name,
    if (dob != null && dob!.trim().isNotEmpty) 'dob': dob,
    'email': email,
    'aanchalNumber': aanchalNumber,
    if (photoUrl != null) 'photoUrl': photoUrl,
    if (aadhaarNumber != null) 'aadhaarNumber': aadhaarNumber,
    'isAadhaarVerified': isAadhaarVerified,
    if (gender != null) 'gender': gender,
  };
}

//  Service 

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _firestore = FirebaseFirestore.instance;
  static final _googleSignIn = GoogleSignIn(
    serverClientId: '574322207892-8kmpanq6tv5nl218kjrfpbpr300p0b23.apps.googleusercontent.com',
  );

  // SharedPreferences keys
  static const _kUid = 'auth_uid';
  static const _kName = 'auth_name';
  static const _kFirstName = 'auth_first_name';
  static const _kLastName = 'auth_last_name';
  static const _kDob = 'auth_dob';
  static const _kEmail = 'auth_email';
  static const _kAanchalNumber = 'auth_aanchal_number';
  static const _kPhotoUrl = 'auth_photo_url';
  static const _kAadhaarNumber = 'auth_aadhaar_number';
  static const _kIsAadhaarVerified = 'auth_is_aadhaar_verified';
  static const _kGender = 'auth_gender';

  //  Helpers 

  static String _generateAanchalNumber() {
    final n = 100000 + Random().nextInt(900000);
    return 'AANCHAL-$n';
  }

  static ({String firstName, String lastName}) _splitDisplayName(String raw) {
    final compact = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) {
      return (firstName: 'Aanchal', lastName: 'User');
    }

    final parts = compact.split(' ');
    return (
      firstName: parts.first,
      lastName: parts.length > 1 ? parts.sublist(1).join(' ') : 'User',
    );
  }

  static Future<UserProfile> _upsertAndLoadProfile(
    User user, {
    String? preferredName,
    String? preferredFirstName,
    String? preferredLastName,
    String? preferredDob,
  }) async {
    final uid = user.uid;
    final docRef = _firestore.collection('users').doc(uid);
    final snap = await docRef.get();

    if (!snap.exists) {
      final split = _splitDisplayName(
        preferredName ?? user.displayName ?? 'Aanchal User',
      );

      final profile = UserProfile(
        uid: uid,
        firstName: (preferredFirstName ?? split.firstName).trim(),
        lastName: (preferredLastName ?? split.lastName).trim(),
        dob: preferredDob,
        email: user.email ?? '',
        aanchalNumber: _generateAanchalNumber(),
      );

      await docRef.set({
        ...profile.toMap(),
        'role': 'user',
        'online': true,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      });

      await _cacheProfile(profile);
      return profile;
    }

    final data = snap.data()!;
    final profile = UserProfile.fromMap(data);
    final existingRole = (data['role'] as String?)?.trim() ?? '';
    final needsNameMigration =
        !data.containsKey('firstName') || !data.containsKey('lastName') || !data.containsKey('name');

    await docRef.set({
      if (needsNameMigration) ...{
        'firstName': profile.firstName,
        'lastName': profile.lastName,
        'name': profile.name,
      },
      if (existingRole.isEmpty) 'role': 'user',
      'online': true,
      'lastSeen': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _cacheProfile(profile);
    return profile;
  }

  //  Register 

  /// Supports both the legacy [name] registration flow and first/last name
  /// profile flow used by incoming features.
  static Future<UserProfile> register({
    String? name,
    String? firstName,
    String? lastName,
    String? dob,
    required String email,
    required String password,
  }) async {
    logInfo(_tag, 'Registering: $email');

    final effectiveName = (() {
      final explicit = (name ?? '').trim();
      if (explicit.isNotEmpty) return explicit;

      final joined = '${firstName ?? ''} ${lastName ?? ''}'.trim();
      return joined.isEmpty ? 'Aanchal User' : joined;
    })();

    final split = _splitDisplayName(effectiveName);

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await credential.user!.updateDisplayName(effectiveName);
    final profile = await _upsertAndLoadProfile(
      credential.user!,
      preferredName: effectiveName,
      preferredFirstName: firstName ?? split.firstName,
      preferredLastName: lastName ?? split.lastName,
      preferredDob: dob,
    );

    logInfo(_tag, 'Registered: ${profile.aanchalNumber}');
    return profile;
  }

  //  Login 

  /// Sign in with email + password, fetch profile from Firestore, and cache.
  static Future<UserProfile> login({
    required String email,
    required String password,
  }) async {
    logInfo(_tag, 'Login: $email');

    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final profile = await _upsertAndLoadProfile(credential.user!);
    logInfo(_tag, 'Logged in: ${profile.aanchalNumber}');
    return profile;
  }

  //  Google Sign-In 

  static Future<UserProfile> signInWithGoogle() async {
    logInfo(_tag, 'Google sign-in started');

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'google-sign-in-cancelled',
        message: 'Google sign-in was cancelled.',
      );
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCred = await _auth.signInWithCredential(credential);
    final user = userCred.user;
    if (user == null) {
      throw Exception('Google sign-in failed. No Firebase user returned.');
    }

    final split = _splitDisplayName(googleUser.displayName ?? 'Aanchal User');

    final profile = await _upsertAndLoadProfile(
      user,
      preferredName: googleUser.displayName,
      preferredFirstName: split.firstName,
      preferredLastName: split.lastName,
    );

    logInfo(_tag, 'Google sign-in success: ${profile.email}');
    return profile;
  }

  static Future<UserProfile?> getProfileFromFirestore(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    final profile = UserProfile.fromMap(doc.data()!);
    await _cacheProfile(profile);
    return profile;
  }

  static Future<void> updateProfile(UserProfile profile) async {
    await _firestore
        .collection('users')
        .doc(profile.uid)
        .set(profile.toMap(), SetOptions(merge: true));
    await _cacheProfile(profile);
  }

  //  Sign Out 

  static Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _firestore.collection('users').doc(uid).set({
        'online': false,
        'lastSeen': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    SosListenerService.instance.stopListening();
    BleService.instance.stop();
    await VoiceTriggerService.instance.stop();
    await _googleSignIn.signOut();
    await _auth.signOut();
    await _clearCachedProfile();
    logInfo(_tag, 'Signed out');
  }

  //  Local Cache 

  static Future<void> _cacheProfile(UserProfile p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUid, p.uid);
    await prefs.setString(_kName, p.name);
    await prefs.setString(_kFirstName, p.firstName);
    await prefs.setString(_kLastName, p.lastName);
    if (p.dob != null && p.dob!.trim().isNotEmpty) {
      await prefs.setString(_kDob, p.dob!);
    } else {
      await prefs.remove(_kDob);
    }
    await prefs.setString(_kEmail, p.email);
    await prefs.setString(_kAanchalNumber, p.aanchalNumber);
    if (p.photoUrl != null) {
      await prefs.setString(_kPhotoUrl, p.photoUrl!);
    } else {
      await prefs.remove(_kPhotoUrl);
    }
    if (p.aadhaarNumber != null) {
      await prefs.setString(_kAadhaarNumber, p.aadhaarNumber!);
    } else {
      await prefs.remove(_kAadhaarNumber);
    }
    await prefs.setBool(_kIsAadhaarVerified, p.isAadhaarVerified);
    if (p.gender != null && p.gender!.trim().isNotEmpty) {
      await prefs.setString(_kGender, p.gender!);
    } else {
      await prefs.remove(_kGender);
    }
  }

  static Future<void> _clearCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUid);
    await prefs.remove(_kName);
    await prefs.remove(_kFirstName);
    await prefs.remove(_kLastName);
    await prefs.remove(_kDob);
    await prefs.remove(_kEmail);
    await prefs.remove(_kAanchalNumber);
    await prefs.remove(_kPhotoUrl);
    await prefs.remove(_kAadhaarNumber);
    await prefs.remove(_kIsAadhaarVerified);
    await prefs.remove(_kGender);
  }

  /// Returns the locally cached profile (no network). Null if not signed in.
  static Future<UserProfile?> getCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_kUid);
    if (uid == null) return null;

    final cachedName = prefs.getString(_kName) ?? '';
    final split = _splitDisplayName(cachedName);

    return UserProfile(
      uid: uid,
      firstName: prefs.getString(_kFirstName) ?? split.firstName,
      lastName: prefs.getString(_kLastName) ?? split.lastName,
      dob: prefs.getString(_kDob),
      email: prefs.getString(_kEmail) ?? '',
      aanchalNumber: prefs.getString(_kAanchalNumber) ?? '',
      photoUrl: prefs.getString(_kPhotoUrl),
      aadhaarNumber: prefs.getString(_kAadhaarNumber),
      isAadhaarVerified: prefs.getBool(_kIsAadhaarVerified) ?? false,
      gender: prefs.getString(_kGender),
    );
  }

  /// Whether a Firebase Auth session is currently active.
  static bool get isSignedIn => _auth.currentUser != null;

  /// The active Firebase user, or null.
  static User? get currentUser => _auth.currentUser;
}
