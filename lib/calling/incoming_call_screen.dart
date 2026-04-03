import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'call_screen.dart';
import 'models.dart';

class IncomingCallScreen extends StatelessWidget {
  final UserProfile currentUser;
  final CallData incomingCall;

  const IncomingCallScreen({
    super.key,
    required this.currentUser,
    required this.incomingCall,
  });

  @override
  Widget build(BuildContext context) {
    return CallScreen(
      currentUser: currentUser,
      peerId: incomingCall.peerId(currentUser.uid),
      peerName: incomingCall.callerName,
      isOutgoing: false,
      incomingCallData: incomingCall,
    );
  }
}
