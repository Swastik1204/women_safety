import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/logger.dart';
import '../../services/auth_service.dart';
import '../../services/cloudinary_service.dart';

class ProfileScreen extends StatefulWidget {
  final UserProfile currentUser;

  const ProfileScreen({super.key, required this.currentUser});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _tag = 'ProfileScreen';

  late UserProfile _profile;
  bool _isLoading = false;
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _aadhaarController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _profile = widget.currentUser;
    _dobController.text = _normalizeDob(_profile.dob ?? '');
  }

  @override
  void dispose() {
    _dobController.dispose();
    _aadhaarController.dispose();
    super.dispose();
  }

  Future<void> _saveDob() async {
    final dob = _normalizeDob(_dobController.text.trim());
    _dobController.text = dob;
    if (!RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(dob)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DOB must be in DD/MM/YYYY format.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedProfile = UserProfile(
        uid: _profile.uid,
        firstName: _profile.firstName,
        lastName: _profile.lastName,
        dob: dob,
        email: _profile.email,
        aanchalNumber: _profile.aanchalNumber,
        photoUrl: _profile.photoUrl,
        aadhaarNumber: _profile.aadhaarNumber,
        isAadhaarVerified: _profile.isAadhaarVerified,
      );

      await AuthService.updateProfile(updatedProfile);

      if (mounted) {
        setState(() {
          _profile = updatedProfile;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DOB saved successfully.')),
        );
      }
    } catch (e) {
      logError(_tag, 'Failed to save DOB', e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save DOB. Please try again.')),
        );
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (pickedFile == null) return;

    setState(() => _isLoading = true);

    try {
      final file = File(pickedFile.path);
      final downloadUrl = await CloudinaryService.instance
        .uploadProfilePhoto(file, _profile.uid);

      final updatedProfile = UserProfile(
        uid: _profile.uid,
        firstName: _profile.firstName,
        lastName: _profile.lastName,
        dob: _profile.dob,
        email: _profile.email,
        aanchalNumber: _profile.aanchalNumber,
        photoUrl: downloadUrl,
        aadhaarNumber: _profile.aadhaarNumber,
        isAadhaarVerified: _profile.isAadhaarVerified,
      );

      await AuthService.updateProfile(updatedProfile);

      if (mounted) {
        setState(() {
          _profile = updatedProfile;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated successfully')),
        );
      }
    } catch (e) {
      logError(_tag, 'Failed to upload photo', e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update profile photo')),
        );
      }
    }
  }

  Future<void> _verifyAadhaar() async {
    if (_profile.dob == null || _profile.dob!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add and save your DOB in profile before Aadhaar verification.',
          ),
        ),
      );
      return;
    }

    final aadhaarNumber = _aadhaarController.text.trim();
    if (aadhaarNumber.length != 12 || int.tryParse(aadhaarNumber) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 12-digit Aadhaar number'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final docRef = FirebaseFirestore.instance
          .collection('aadhar_ver')
          .doc(aadhaarNumber);

      final docSnap = await docRef.get();

      if (docSnap.exists) {
        final data = docSnap.data();
        if (data != null &&
            data['First_name'] == _profile.firstName &&
            data['Last_name'] == _profile.lastName &&
            data['dob'] == _profile.dob) {
          final updatedProfile = UserProfile(
            uid: _profile.uid,
            firstName: _profile.firstName,
            lastName: _profile.lastName,
            dob: _profile.dob,
            email: _profile.email,
            aanchalNumber: _profile.aanchalNumber,
            photoUrl: _profile.photoUrl,
            aadhaarNumber: aadhaarNumber,
            isAadhaarVerified: true,
            gender: data['gender'] as String?,
          );

          await AuthService.updateProfile(updatedProfile);

          if (mounted) {
            setState(() {
              _profile = updatedProfile;
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Aadhaar verification successful!')),
            );
          }
        } else {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Aadhaar verification failed. Details do not match.',
                ),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Aadhaar verification failed. Record not found.'),
            ),
          );
        }
      }
    } catch (e) {
      logError(_tag, 'Aadhaar verification failed', e);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An error occurred during verification.'),
          ),
        );
      }
    }
  }

  String _normalizeDob(String input) {
    final digitsOnly = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length == 8) {
      return '${digitsOnly.substring(0, 2)}/${digitsOnly.substring(2, 4)}/${digitsOnly.substring(4, 8)}';
    }
    return input;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile'), elevation: 0),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: _profile.photoUrl != null
                            ? NetworkImage(_profile.photoUrl!)
                            : null,
                        child: _profile.photoUrl == null
                            ? Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.grey.shade400,
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _isLoading ? null : _pickAndUploadImage,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(8),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Name Field
                _buildInfoTile(
                  context: context,
                  title: 'Name',
                  subtitle: '${_profile.firstName} ${_profile.lastName}',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 16),

                // Contact Details (Email / Aanchal Number)
                _buildInfoTile(
                  context: context,
                  title: 'Email',
                  subtitle: _profile.email.isNotEmpty
                      ? _profile.email
                      : 'No email provided',
                  icon: Icons.email_outlined,
                ),
                const SizedBox(height: 16),

                _buildInfoTile(
                  context: context,
                  title: 'Aanchal Number',
                  subtitle: _profile.aanchalNumber,
                  icon: Icons.tag,
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _dobController,
                  keyboardType: TextInputType.datetime,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                    _DobTextInputFormatter(),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Date of Birth (DD/MM/YYYY)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).cardTheme.color,
                    prefixIcon: const Icon(Icons.calendar_today_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _saveDob,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save DOB'),
                ),
                const SizedBox(height: 32),

                // Aadhaar Section
                const Text(
                  'Aadhaar Verification',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                if (_profile.isAadhaarVerified)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, color: Colors.green),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Identity Verified',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              'Aadhaar: **** **** ${_profile.aadhaarNumber?.substring(_profile.aadhaarNumber!.length - 4)}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _aadhaarController,
                        keyboardType: TextInputType.number,
                        maxLength: 12,
                        decoration: InputDecoration(
                          labelText: 'Enter 12-digit Aadhaar Number',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).cardTheme.color,
                          prefixIcon: const Icon(Icons.credit_card),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _isLoading ? null : _verifyAadhaar,
                        icon: const Icon(Icons.shield),
                        label: const Text('Verify Identity'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: isDark ? Border.all(color: Colors.white12, width: 1) : null,
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DobTextInputFormatter extends TextInputFormatter {
  const _DobTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text;
    final buffer = StringBuffer();

    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if ((i == 1 || i == 3) && i != digits.length - 1) {
        buffer.write('/');
      }
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
