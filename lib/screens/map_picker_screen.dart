import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';

/// Returns a record (lat, lng, name) or null if cancelled.
class MapPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  const MapPickerScreen({super.key, this.initialLat, this.initialLng});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final MapController _mapCtrl = MapController();
  late LatLng _center;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _center = LatLng(
      widget.initialLat ?? 33.5731, // Casablanca par défaut
      widget.initialLng ?? -7.5898,
    );
  }

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    final name = await LocationService.reverseGeocode(
        _center.latitude, _center.longitude);
    if (!mounted) return;
    Navigator.of(context).pop((
      lat: _center.latitude,
      lng: _center.longitude,
      name: name ?? 'Lieu sélectionné',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Choisir un lieu',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _confirming ? null : _confirm,
              child: _confirming
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Confirmer',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onPositionChanged: (pos, _) {
                if (pos.center != null) {
                  setState(() => _center = pos.center!);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.vocal_todo',
              ),
            ],
          ),
          // Crosshair
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_pin,
                    color: Color(0xFF6366F1), size: 44),
                SizedBox(height: 44), // offset for icon anchor
              ],
            ),
          ),
          // Coordinates overlay
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_center.latitude.toStringAsFixed(5)}, '
                '${_center.longitude.toStringAsFixed(5)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
