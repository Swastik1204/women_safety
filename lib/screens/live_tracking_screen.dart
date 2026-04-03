import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LiveTrackingScreen extends StatelessWidget {
  final String sessionId;
  final String fromName;

  const LiveTrackingScreen({
    super.key,
    required this.sessionId,
    required this.fromName,
  });

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final locationsRef = FirebaseFirestore.instance
        .collection('sos_sessions')
        .doc(sessionId)
        .collection('locations')
        .orderBy('timestamp', descending: false);

    return Scaffold(
      appBar: AppBar(title: Text('Live Tracking - $fromName')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: locationsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('Waiting for live location updates...'),
            );
          }

          final points = <LatLng>[];
          for (final d in docs) {
            final data = d.data();
            final lat = _toDouble(data['lat']);
            final lng = _toDouble(data['lng']);
            if (lat == 0 && lng == 0) continue;
            points.add(LatLng(lat, lng));
          }

          if (points.isEmpty) {
            return const Center(
              child: Text('No valid location points yet.'),
            );
          }

          final latest = points.last;

          return GoogleMap(
            initialCameraPosition: CameraPosition(
              target: latest,
              zoom: 16,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('live_latest'),
                position: latest,
                infoWindow: InfoWindow(title: '$fromName - latest location'),
              ),
            },
            polylines: {
              if (points.length > 1)
                Polyline(
                  polylineId: const PolylineId('live_path'),
                  points: points,
                  width: 5,
                  color: Colors.red,
                ),
            },
            myLocationEnabled: false,
            mapToolbarEnabled: true,
            zoomControlsEnabled: false,
            compassEnabled: true,
          );
        },
      ),
    );
  }
}
