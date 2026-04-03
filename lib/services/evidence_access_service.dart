import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/logger.dart';
import 'auth_service.dart';

const _tag = 'EvidenceAccessService';

class EvidenceAccessService {
  EvidenceAccessService._();
  static final EvidenceAccessService instance = EvidenceAccessService._();

  Future<bool> verifyCode({
    required String sessionId,
    required String code,
  }) async {
    final token = await AuthService.currentUser?.getIdToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.apiEvidenceVerify),
            headers: headers,
            body: jsonEncode({
              'sessionId': sessionId,
              'code': code,
            }),
          )
          .timeout(AppConfig.apiTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        logWarn(
          _tag,
          'Evidence verify failed: ${response.statusCode} ${response.body}',
        );
        return false;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['accessGranted'] == true;
    } catch (e) {
      logError(_tag, 'Evidence verify request failed: $e');
      return false;
    }
  }
}
