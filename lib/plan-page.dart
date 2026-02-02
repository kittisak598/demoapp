import 'dart:async';
import 'dart:convert'; // สำหรับแปลง JSON จาก OSRM
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'; // ใช้ OSM
import 'package:latlong2/latlong.dart'; // ใช้ LatLng ของ OSM
import 'package:http/http.dart' as http;
import 'package:projectapp/upbus-page.dart'; // ใช้ยิง API ขอเส้นทาง
import 'package:flutter/services.dart' show rootBundle;
// import 'models/bus_model.dart';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:flutter/services.dart' show rootBundle;

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
  List<LatLng> _currentRoute = [];

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
                  StreamBuilder(
                    stream: FirebaseFirestore.instance
                        .collection('Bus stop')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const MarkerLayer(markers: []);
                      return MarkerLayer(
                        markers: snapshot.data!.docs.map((doc) {
                          var data = doc.data();
                          return Marker(
                            point: LatLng(
                              double.parse(data['lat'].toString()),
                              double.parse(data['long'].toString()),
                            ),
                            // ขยาย width และ height เพื่อให้มีพื้นที่สำหรับแถบข้อความที่จะลอยขึ้นมา
                            width: 200,
                            height: 100,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  // เมื่อกดที่ป้าย: ถ้าเป็นป้ายเดิมให้ปิด (null) ถ้าเป็นป้ายใหม่ให้เปิด (เก็บ doc.id)
                                  selectedBusStopId =
                                      (selectedBusStopId == doc.id)
                                      ? null
                                      : doc.id;
                                });
                              },
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  // --- ส่วนที่ 1: แถบข้อความสีขาว (จะแสดงเฉพาะป้ายที่ถูกเลือก) ---
                                  if (selectedBusStopId == doc.id)
                                    Positioned(
                                      top: 0, // ให้ลอยอยู่ด้านบนสุดของ Stack
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors
                                              .white, // พื้นหลังสีขาวตามรูป
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          data['name']
                                              .toString(), // ดึงชื่อป้ายจาก Firebase
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),

                                  // --- ส่วนที่ 2: ไอคอนป้ายรถเมล์ (อยู่ด้านล่างเสมอ) ---
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Image.asset(
                                      'assets/images/bus-stopicon.png',
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),

            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Future<Map<int, List<LatLng>>> _loadAllRoutes() async {
    Map<int, List<LatLng>> routes = {};

    for (int i = 1; i <= 3; i++) {
      final data = await rootBundle.loadString(
        'assets/data/bus_route$i.geojson',
      );
      final json = jsonDecode(data);
      final List coords = json['features'][0]['geometry']['coordinates'];

      routes[i] = coords
          .map<LatLng>((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
          .toList();
    }

    return routes;
  }

  List<LatLng> _mergeRoutes(Map<int, List<LatLng>> routes) {
    final Distance d = const Distance();
    const double CONNECT_THRESHOLD = 50; // เมตร

    List<LatLng> merged = [];

    for (final route in routes.values) {
      if (merged.isEmpty) {
        merged.addAll(route);
        continue;
      }

      final last = merged.last;
      final first = route.first;

      // ต่อได้เฉพาะถ้าใกล้จริง
      if (d(last, first) <= CONNECT_THRESHOLD) {
        merged.addAll(route);
      }
    }

    return merged;
  }

  int _nearestIndex(LatLng stop, List<LatLng> route) {
    final Distance d = const Distance();
    double minDist = double.infinity;
    int nearest = 0;

    for (int i = 0; i < route.length; i++) {
      final dist = d(stop, route[i]);
      if (dist < minDist) {
        minDist = dist;
        nearest = i;
      }
    }
    return nearest;
  }

  double _distanceToRoute(LatLng stop, List<LatLng> route) {
    final Distance d = const Distance();
    double minDist = double.infinity;

    for (final p in route) {
      final dist = d(stop, p);
      if (dist < minDist) minDist = dist;
    }
    return minDist;
  }

  // --- ฟังก์ชันหลัก: ดึงพิกัดแล้ววาดเส้นด้วย แทนOSRM ---
  Future<void> _onSearchAndDrawRouteOSM() async {
    if (_selectedSourceId == null || _selectedDestinationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกต้นทางและปลายทาง')),
      );
      return;
    }

    // 1) ดึงพิกัด
    final start = await _getCoordsFromFirebase(_selectedSourceId!);
    final end = await _getCoordsFromFirebase(_selectedDestinationId!);
    if (start == null || end == null) return;

    // 2) โหลดทุกเส้น (3 สาย)
    final routes = await _loadAllRoutes();

    // หาเส้นที่ start end อยู่สายเดียวกัน
    int? matchedRoute;

    routes.forEach((id, route) {
      final ds = _distanceToRoute(start, route);
      final de = _distanceToRoute(end, route);

      if (ds < 400 && de < 400) {
        // เมตร
        matchedRoute = id;
      }
    });

    if (matchedRoute == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ต้องเปลี่ยนสายรถ')));
      return;
    }

    // ใช้เฉพาะสายนี้
    final route = routes[matchedRoute]!;

    // ตัดเส้นจาก A → B
    final idxA = _nearestIndex(start, route);
    final idxB = _nearestIndex(end, route);

    final path = idxA <= idxB
        ? route.sublist(idxA, idxB + 1)
        : route.sublist(idxB, idxA + 1).reversed.toList();

    // 5) วาด
    setState(() {
      _polylines.clear();
      _markers.clear();

      _polylines.add(
        Polyline(points: path, strokeWidth: 5, color: Colors.blueAccent),
      );

      _markers.add(
        Marker(
          point: start,
          width: 40,
          height: 40,
          child: const Icon(Icons.my_location, color: Colors.blue),
        ),
      );

      _markers.add(
        Marker(
          point: end,
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: Colors.red),
        ),
      );
    });

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(path),

        padding: const EdgeInsets.all(40),
      ),
    );
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
