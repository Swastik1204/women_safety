class PhoneUtils {
  static String normalize(String? phone) {
    if (phone == null || phone.isEmpty) return '';

    var cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '').trim();
    if (cleaned.startsWith('+91') && cleaned.length == 13) {
      return cleaned;
    }

    if (cleaned.startsWith('+') && !cleaned.startsWith('+91')) {
      return cleaned;
    }

    if (cleaned.startsWith('91') && cleaned.length == 12) {
      return '+$cleaned';
    }

    if (cleaned.startsWith('0') && cleaned.length == 11) {
      cleaned = cleaned.substring(1);
    }

    if (cleaned.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(cleaned)) {
      return '+91$cleaned';
    }

    return cleaned;
  }
}