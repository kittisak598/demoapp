import 'dart:async';
import 'dart:convert'; // สำหรับแปลง JSON จาก OSRM
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'; // ใช้ OSM
import 'package:latlong2/latlong.dart'; // ใช้ LatLng ของ OSM
import 'package:http/http.dart' as http; // ใช้ยิง API ขอเส้นทาง

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  int _selectedBottomIndex = 3;

  String? _selectedSourceId;
  String? _selectedDestinationId;

  // --- ตัวแปรสำหรับ OSM ---
  final MapController _mapController = MapController();
  List<Polyline> _polylines = []; // เส้นทางเก็บเป็น List
  List<Marker> _markers = []; // หมุดเก็บเป็น List

  // พิกัดเริ่มต้น (ม.พะเยา)
  static const LatLng _kUniversity = LatLng(
    19.03011372185138,
    99.89781512200192,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: _buildEndDrawer(),
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),

            // --- ส่วน Input (เลือกต้นทาง/ปลายทาง) ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildDropdown(
                    "ต้นทาง (Start)",
                    Icons.my_location,
                    Colors.blue,
                    _selectedSourceId,
                    (val) {
                      setState(() => _selectedSourceId = val);
                    },
                  ),
                  Container(
                    height: 20,
                    padding: const EdgeInsets.only(left: 23),
                    alignment: Alignment.centerLeft,
                    child: Container(width: 2, color: Colors.grey.shade300),
                  ),
                  _buildDropdown(
                    "ปลายทาง (Destination)",
                    Icons.location_on,
                    Colors.red,
                    _selectedDestinationId,
                    (val) {
                      setState(() => _selectedDestinationId = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton.icon(
                      onPressed: _onSearchAndDrawRouteOSM, // เรียกฟังก์ชันใหม่
                      icon: const Icon(Icons.directions),
                      label: const Text("แสดงเส้นทาง"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFCE6BFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- ส่วนแสดงแผนที่ OSM ---
            Expanded(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _kUniversity,
                  initialZoom: 14.5,
                ),
                children: [
                  // Layer 1: แผนที่
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.upbus',
                  ),
                  // Layer 2: เส้นทาง
                  PolylineLayer(polylines: _polylines),
                  // Layer 3: หมุด
                  MarkerLayer(markers: _markers),
                ],
              ),
            ),

            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // --- ฟังก์ชันหลัก: ดึงพิกัดแล้ววาดเส้นด้วย OSRM ---
  Future<void> _onSearchAndDrawRouteOSM() async {
    if (_selectedSourceId == null || _selectedDestinationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกต้นทางและปลายทาง')),
      );
      return;
    }

    // 1. ดึงพิกัดจาก Firebase
    LatLng? startCoords = await _getCoordsFromFirebase(_selectedSourceId!);
    LatLng? endCoords = await _getCoordsFromFirebase(_selectedDestinationId!);

    if (startCoords == null || endCoords == null) return;

    // 2. เรียก OSRM API เพื่อหาเส้นทาง
    // OSRM ใช้ format: longitude,latitude (สลับกับ Google)
    final String url =
        'http://router.project-osrm.org/route/v1/driving/'
        '${startCoords.longitude},${startCoords.latitude};'
        '${endCoords.longitude},${endCoords.latitude}'
        '?overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        if (data['routes'] == null || (data['routes'] as List).isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ไม่พบเส้นทาง')));
          return;
        }

        // ดึงจุด Coordinates จาก GeoJSON
        final route = data['routes'][0];
        final geometry = route['geometry'];
        final List<dynamic> coordinates = geometry['coordinates'];

        // แปลงเป็น List<LatLng> ของ flutter_map
        List<LatLng> routePoints = coordinates.map((coord) {
          return LatLng(coord[1].toDouble(), coord[0].toDouble());
        }).toList();

        // 3. อัปเดต State วาดเส้นและหมุด
        setState(() {
          // เคลียร์ของเก่า
          _polylines.clear();
          _markers.clear();

          // เพิ่มเส้น
          _polylines.add(
            Polyline(
              points: routePoints,
              strokeWidth: 5.0,
              color: Colors.blueAccent,
            ),
          );

          // เพิ่มหมุดต้นทาง
          _markers.add(
            Marker(
              point: startCoords,
              width: 60,
              height: 60,
              child: const Icon(
                Icons.my_location,
                color: Colors.blue,
                size: 40,
              ),
            ),
          );

          // เพิ่มหมุดปลายทาง
          _markers.add(
            Marker(
              point: endCoords,
              width: 60,
              height: 60,
              child: const Icon(Icons.location_on, color: Colors.red, size: 40),
            ),
          );
        });

        // 4. ซูมแผนที่ให้เห็นทั้งเส้น
        // ใช้ bounds จากจุดทั้งหมด
        LatLngBounds bounds = LatLngBounds.fromPoints(routePoints);
        // ขยายขอบเล็กน้อยเพื่อให้สวยงาม
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
        );
      } else {
        print("Error calling OSRM API: ${response.statusCode}");
      }
    } catch (e) {
      print("Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ')),
      );
    }
  }

  // Helper: ดึงพิกัดจาก Firestore (เหมือนเดิม แต่ Return LatLng ของ OSM)
  Future<LatLng?> _getCoordsFromFirebase(String docId) async {
    try {
      var doc = await FirebaseFirestore.instance
          .collection('Bus stop')
          .doc(docId)
          .get();
      if (doc.exists) {
        var data = doc.data() as Map<String, dynamic>;
        double lat = double.parse(data['lat'].toString());
        double lng = double.parse(data['long'].toString());
        return LatLng(lat, lng);
      }
    } catch (e) {
      print("Error fetching coords: $e");
    }
    return null;
  }

  // --- Widgets UI (คงเดิมไว้เกือบทั้งหมด) ---
  Widget _buildDropdown(
    String label,
    IconData icon,
    Color color,
    String? val,
    Function(String?) onChange,
  ) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Bus stop').snapshots(),
      builder: (context, snapshot) {
        List<DropdownMenuItem<String>> items = [];
        if (snapshot.hasData) {
          items = snapshot.data!.docs
              .map(
                (d) => DropdownMenuItem(
                  value: d.id,
                  child: Text((d.data() as Map)['name'] ?? '-'),
                ),
              )
              .toList();
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: val,
              isExpanded: true,
              items: items,
              onChanged: onChange,
              hint: Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF9C27B0),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(15),
          bottomRight: Radius.circular(15),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Text(
            'PLANNER',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const ListTile(
              leading: CircleAvatar(child: Icon(Icons.person)),
              title: Text('Profile'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF9C27B0),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(15),
          topRight: Radius.circular(15),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: SizedBox(
        height: 70,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _bottomNavItem(0, Icons.location_on, 'Live'),
            _bottomNavItem(1, Icons.directions_bus, 'Stop'),
            _bottomNavItem(2, Icons.map, 'Route'),
            _bottomNavItem(3, Icons.alt_route, 'Plan'),
            _bottomNavItem(4, Icons.feedback, 'Feed'),
          ],
        ),
      ),
    );
  }

  Widget _bottomNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedBottomIndex == index;
    return InkWell(
      onTap: () {
        if (index == _selectedBottomIndex) return;
        switch (index) {
          case 0:
            Navigator.pushReplacementNamed(context, '/'); // กลับหน้าหลัก
            break;
          case 1:
            Navigator.pushReplacementNamed(context, '/busStop');
            break;
          case 2:
            Navigator.pushReplacementNamed(context, '/route');
            break;
          case 3:
            // อยู่หน้านี้อยู่แล้ว
            break;
          case 4:
            Navigator.pushReplacementNamed(context, '/feedback');
            break;
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: isSelected ? 28 : 24),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
