import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'services/route_service.dart';
import 'services/notification_service.dart';
import 'models/bus_model.dart';

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

String? selectedBusStopId;

class UpBusHomePage extends StatefulWidget {
  const UpBusHomePage({super.key});

  @override
  State<UpBusHomePage> createState() => _UpBusHomePageState();
}

class _UpBusHomePageState extends State<UpBusHomePage> {
  int _selectedRouteIndex = 0;
  int _selectedBottomIndex = 0;
  bool _notifyNearBusStop = false;

  // สายรถที่เลือกสำหรับ notification (null = ทุกสาย)
  String? _selectedNotifyRouteId;

  final MapController _mapController = MapController();

  final DatabaseReference _gpsRef = FirebaseDatabase.instance.ref("GPS");

  List<Polyline> _allPolylines = []; // เก็บเส้นทางทั้งหมด 3 สาย
  List<Polyline> _displayPolylines = []; // เก็บเส้นทางที่จะแสดงผลปัจจุบัน
  Polyline? _routeNamorPKY;

  // --- Multi-Bus Tracking Variables ---
  StreamSubscription? _busSubscription;
  StreamSubscription<Position>? _positionSubscription;

  List<Bus> _buses = [];
  Bus? _closestBus;
  LatLng? _userPosition;
  bool _hasAlerted = false; // ป้องกันการแจ้งเตือนซ้ำ

  static const double _alertDistanceMeters = 500.0;

  static const LatLng _kUniversity = LatLng(
    19.03011372185138,
    99.89781512200192,
  );

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _listenToBusLocation();
    _startLocationTracking();
    _loadAllRoutes();
  }

  //future ดึงเส้นทาง
  Future<void> _loadAllRoutes() async {
    try {
      // โหลด 3 ไฟล์ (เปลี่ยน path ให้ตรงกับไฟล์ของคุณ)
      // 0=หน้ามอ(เขียว), 1=หอใน(แดง), 2=ICT(น้ำเงิน)
      Polyline routeNamor = await _parseGeoJson(
        'assets/data/bus_route1เส้นทางก่อนบ่าย2.geojson',
        const Color.fromRGBO(68, 182, 120, 1),
      );
      //เส้นทางหลังบ่ายสอง
      _routeNamorPKY = await _parseGeoJson(
        'assets/data/bus_route1.geojson',
        const Color.fromRGBO(68, 182, 120, 1),
      );
      Polyline routeHornai = await _parseGeoJson(
        'assets/data/bus_route2.geojson',
        const Color.fromRGBO(255, 56, 89, 1),
      );
      Polyline routeICT = await _parseGeoJson(
        'assets/data/bus_route3.geojson',
        const Color.fromRGBO(17, 119, 252, 1),
      );

      if (!mounted) return;
      setState(() {
        _allPolylines = [routeNamor, routeHornai, routeICT];
        _displayPolylines = _allPolylines; // เริ่มต้นแสดงทั้งหมด
      });
    } catch (e) {
      debugPrint("Error loading routes: $e");
    }
  }

  Future<Polyline> _parseGeoJson(String assetPath, Color color) async {
    String data = await rootBundle.loadString(assetPath);
    var jsonResult = jsonDecode(data);
    List<LatLng> points = [];

    var features = jsonResult['features'] as List;
    for (var feature in features) {
      var geometry = feature['geometry'];
      if (geometry['type'] == 'LineString') {
        var coordinates = geometry['coordinates'] as List;
        for (var coord in coordinates) {
          // GeoJSON เป็น [Long, Lat] แต่ FlutterMap ใช้ [Lat, Long] ต้องสลับ
          points.add(LatLng(coord[1], coord[0]));
        }
      }
    }
    return Polyline(points: points, color: color, strokeWidth: 4.0);
  }

  //ฟังก์ชันดึงเส้นทางตามปุ่ม
  void _filterRoutes(int index) {
    if (_allPolylines.isEmpty) return;

    setState(() {
      final now = DateTime.now();

      // สร้างเวลาจุดอ้างอิงของวันนี้
      final fiveAM = DateTime(now.year, now.month, now.day, 5, 0); // 05:00 น.
      final twoPM = DateTime(now.year, now.month, now.day, 14, 0); // 14:00 น.

      // เช็คว่า "ตอนนี้" อยู่ในช่วง ตี 5 ถึง บ่าย 2 หรือไม่
      // (เวลาต้อง >= 05:00 และ < 14:00)
      bool isMorningRange = now.isAfter(fiveAM) && now.isBefore(twoPM);

      Polyline currentNamor;

      if (isMorningRange) {
        // ช่วง 05:00 - 13:59:59 ใช้เส้นทางก่อนบ่าย 2
        currentNamor = _allPolylines[0];
        print("โหมด: 05:00 - 14:00 (ใช้เส้นทางก่อนบ่าย 2)");
      } else {
        // หลัง 14:00 เป็นต้นไป หรือก่อนตี 5 ใช้เส้นทางหลัก
        // หมายเหตุ: _routeNamorPKY ในที่นี้คือไฟล์ bus_route1.geojson ที่เราโหลดแยกไว้
        currentNamor = _routeNamorPKY ?? _allPolylines[0];
        print("โหมด: หลัง 14:00 (ใช้เส้นทาง bus_route1)");
      }

      // อัปเดตการแสดงผล
      if (index == 0) {
        _displayPolylines = [currentNamor, _allPolylines[1], _allPolylines[2]];
      } else if (index == 1) {
        _displayPolylines = [currentNamor];
      } else if (index == 2) {
        _displayPolylines = [_allPolylines[1]];
      } else if (index == 3) {
        _displayPolylines = [_allPolylines[2]];
      }
    });
  }

  Future<void> _initializeServices() async {
    await NotificationService.initialize();
  }

  @override
  void dispose() {
    _busSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  /// ติดตามตำแหน่งผู้ใช้
  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((Position position) {
          if (!mounted) return;
          setState(() {
            _userPosition = LatLng(position.latitude, position.longitude);
          });
          _updateClosestBus();
        });
  }

  void _listenToBusLocation() {
    _busSubscription = _gpsRef.onValue.listen((event) {
      final data = event.snapshot.value;
      if (data == null || !mounted) return;

      List<Bus> newBuses = [];

      if (data is Map) {
        // รองรับหลายคัน: GPS/{busId}/lat, lng, name
        data.forEach((key, value) {
          if (value is Map &&
              value.containsKey('lat') &&
              value.containsKey('lng')) {
            try {
              newBuses.add(Bus.fromFirebase(key.toString(), value));
            } catch (e) {
              print('Error parsing bus $key: $e');
            }
          }
        });

        // Fallback: ถ้าไม่มี nested structure ให้ใช้แบบเดิม (single bus)
        if (newBuses.isEmpty &&
            data.containsKey('lat') &&
            data.containsKey('lng')) {
          newBuses.add(Bus.fromFirebase('bus_1', data));
        }
      }

      setState(() {
        _buses = newBuses;
      });
      _updateClosestBus();
    });
  }

  /// หาคันที่ใกล้ที่สุด + แจ้งเตือน
  Future<void> _updateClosestBus() async {
    if (_buses.isEmpty) return;

    final userPos = _userPosition ?? _kUniversity;
    final Distance distance = const Distance();

    // คำนวณระยะทางทุกคัน
    List<Bus> busesWithDistance = [];
    for (final bus in _buses) {
      // ลองใช้ road distance ก่อน, fallback เป็น straight-line
      double? roadDist = await RouteService.getRoadDistance(
        userPos,
        bus.position,
      );
      double dist =
          roadDist ?? distance.as(LengthUnit.Meter, userPos, bus.position);
      busesWithDistance.add(bus.copyWithDistance(dist));
    }

    // เรียงจากใกล้ไปไกล
    busesWithDistance.sort(
      (a, b) => (a.distanceToUser ?? double.infinity).compareTo(
        b.distanceToUser ?? double.infinity,
      ),
    );

    if (!mounted) return;
    setState(() {
      _buses = busesWithDistance;
      _closestBus = busesWithDistance.isNotEmpty
          ? busesWithDistance.first
          : null;
    });

    // แจ้งเตือนถ้าเข้าใกล้กว่า 500 เมตร (เฉพาะสายที่เลือก)
    if (_notifyNearBusStop) {
      // Filter รถตามสายที่เลือก
      Bus? targetBus;
      if (_selectedNotifyRouteId == null) {
        // ถ้าเลือก "ทุกสาย" ใช้รถที่ใกล้ที่สุด
        targetBus = _closestBus;
      } else {
        // หารถที่ใกล้ที่สุดในสายที่เลือก
        final filteredBuses = busesWithDistance
            .where((b) => b.routeId == _selectedNotifyRouteId)
            .toList();
        targetBus = filteredBuses.isNotEmpty ? filteredBuses.first : null;
      }

      if (targetBus != null) {
        final targetDist = targetBus.distanceToUser ?? double.infinity;
        if (targetDist <= _alertDistanceMeters && !_hasAlerted) {
          _hasAlerted = true;
          await NotificationService.alertBusNearby(
            busName: targetBus.name,
            distanceMeters: targetDist,
          );
        } else if (targetDist > _alertDistanceMeters) {
          _hasAlerted = false; // Reset เมื่อออกนอกระยะ
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      endDrawer: _buildEndDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _kUniversity,
                                initialZoom: 16.5,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.upbus.app',
                                ),
                                PolylineLayer(polylines: _displayPolylines),
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
                                            double.parse(
                                              data['lat'].toString(),
                                            ),
                                            double.parse(
                                              data['long'].toString(),
                                            ),
                                          ),
                                          // ขยาย width และ height เพื่อให้มีพื้นที่สำหรับแถบข้อความที่จะลอยขึ้นมา
                                          width: 200,
                                          height: 100,
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                // เมื่อกดที่ป้าย: ถ้าเป็นป้ายเดิมให้ปิด (null) ถ้าเป็นป้ายใหม่ให้เปิด (เก็บ doc.id)
                                                selectedBusStopId =
                                                    (selectedBusStopId ==
                                                        doc.id)
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
                                                    top:
                                                        0, // ให้ลอยอยู่ด้านบนสุดของ Stack
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors
                                                            .white, // พื้นหลังสีขาวตามรูป
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        boxShadow: const [
                                                          BoxShadow(
                                                            color:
                                                                Colors.black26,
                                                            blurRadius: 4,
                                                            offset: Offset(
                                                              0,
                                                              2,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      child: Text(
                                                        data['name']
                                                            .toString(), // ดึงชื่อป้ายจาก Firebase
                                                        style: const TextStyle(
                                                          color: Colors.black,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),

                                                // --- ส่วนที่ 2: ไอคอนป้ายรถเมล์ (อยู่ด้านล่างเสมอ) ---
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 10,
                                                      ),
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
                                // --- Live Bus Markers ---
                                MarkerLayer(
                                  markers: _buses.map((bus) {
                                    final isClosest = _closestBus?.id == bus.id;
                                    return Marker(
                                      point: bus.position,
                                      width: 80,
                                      height: 80,
                                      child: Image.asset(
                                        'assets/images/busiconall.png',
                                        fit: BoxFit.contain,
                                      ),
                                    );
                                  }).toList(),
                                ),
                                // --- User Location Marker ---
                                if (_userPosition != null)
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: _userPosition!,
                                        width: 50,
                                        height: 50,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // วงกลมรัศมีแสดงความแม่นยำ
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withOpacity(
                                                  0.2,
                                                ),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.blue
                                                      .withOpacity(0.5),
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                            // จุดตำแหน่งผู้ใช้
                                            Container(
                                              width: 16,
                                              height: 16,
                                              decoration: BoxDecoration(
                                                color: Colors.blue,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 3,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.blue
                                                        .withOpacity(0.4),
                                                    blurRadius: 8,
                                                    spreadRadius: 2,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            Positioned(
                              top: 16,
                              right: 16,
                              child: Column(
                                children: [
                                  _floatingMapIcon(
                                    icon: _notifyNearBusStop
                                        ? Icons.notifications_active
                                        : Icons.notifications_none,
                                    onTap: _onNotificationIconTap,
                                  ),
                                  const SizedBox(height: 12),
                                  _floatingMapIcon(
                                    icon: Icons.my_location,
                                    onTap: _goToMyLocation,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // --- Proximity Alert Box ---
                  if (_notifyNearBusStop) _buildProximityAlertBox(),

                  // ส่วนปุ่มเลือกสถานที่
                  Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _routeButton(
                            label: 'ภาพรวม',
                            color: const Color.fromRGBO(143, 55, 203, 1),
                            isSelected: _selectedRouteIndex == 0,
                            onPressed: () {
                              setState(() => _selectedRouteIndex = 0);
                              _filterRoutes(0);
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _routeButton(
                            label: 'หน้ามอ',
                            color: const Color.fromRGBO(68, 182, 120, 1),
                            isSelected: _selectedRouteIndex == 1,
                            onPressed: () {
                              setState(() => _selectedRouteIndex = 1);
                              _filterRoutes(1);
                            },
                          ),
                        ),

                        const SizedBox(width: 6),
                        Expanded(
                          child: _routeButton(
                            label: 'หอใน',
                            color: const Color.fromRGBO(255, 56, 89, 1),
                            isSelected: _selectedRouteIndex == 2,
                            onPressed: () {
                              setState(() => _selectedRouteIndex = 2);
                              _filterRoutes(2);
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _routeButton(
                            label: 'ICT',
                            color: const Color.fromRGBO(17, 119, 252, 1),
                            isSelected: _selectedRouteIndex == 3,
                            onPressed: () {
                              setState(() => _selectedRouteIndex = 3);
                              _filterRoutes(3);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildBottomBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ส่วนฟังก์ชันย่อยอื่นๆ (BottomBar ฯลฯ) คงเดิมตามที่แก้ล่าสุด ---

  // (คัดลอก Widget ย่อยด้านล่างจากโค้ดเดิมของคุณมาใส่ต่อได้เลยครับ)
  // ...

  Widget _routeButton({
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        // ถ้าถูกเลือก (isSelected) ให้ใช้สีประจำสาย (color)
        // ถ้าไม่ถูกเลือก ให้เป็นสีขาว (Colors.white)
        backgroundColor: isSelected ? color : Colors.white,
        // ถ้าถูกเลือก ตัวหนังสือเป็นสีขาว ถ้าไม่เลือก ให้เป็นสีเดียวกับสายรถ
        foregroundColor: isSelected ? Colors.white : color,
        //ขอบเพื่อให้ปุ่มสีขาวดูชัดขึ้น
        side: BorderSide(color: color, width: 2),
        //จุดที่ปรับขนาด
        //กำหนดความสูงขั้นต่ำ
        minimumSize: const Size(double.infinity, 30),
        //paddingดันขนาดปุ่ม
        padding: const EdgeInsets.symmetric(vertical: 14),
        elevation: isSelected ? 4 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
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
            'UP BUS',
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

  Widget _floatingMapIcon({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.grey.shade800),
        ),
      ),
    );
  }

  Future<void> _goToMyLocation() async {
    if (_userPosition != null) {
      _mapController.move(_userPosition!, 17);
    } else {
      // ถ้ายังไม่มีตำแหน่ง ให้ขอ permission อีกครั้ง
      await _startLocationTracking();
      if (_userPosition != null) {
        _mapController.move(_userPosition!, 17);
      }
    }
  }

  Future<void> _onNotificationIconTap() async {
    await _showRouteSelectionDialog();
  }

  /// แสดง Dialog เลือกสายรถที่จะแจ้งเตือน
  Future<void> _showRouteSelectionDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.notifications_active, color: Color(0xFF9C27B0)),
            SizedBox(width: 8),
            Text('เลือกสายที่จะแจ้งเตือน'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ตัวเลือก "ทุกสาย"
            _routeSelectionTile(
              title: 'รถทุกสาย',
              subtitle: 'แจ้งเตือนเมื่อรถสายใดก็ได้เข้าใกล้',
              color: const Color(0xFF9C27B0),
              icon: Icons.all_inclusive,
              isSelected: _notifyNearBusStop && _selectedNotifyRouteId == null,
              onTap: () {
                setState(() {
                  _notifyNearBusStop = true;
                  _selectedNotifyRouteId = null;
                  _hasAlerted = false;
                });
                Navigator.pop(context);
                _showNotificationSnackBar('ทุกสาย');
              },
            ),
            const Divider(),
            // สายรถแต่ละสาย
            ...BusRoute.allRoutes.map(
              (route) => _routeSelectionTile(
                title: '${route.id} ${route.name}',
                subtitle: 'แจ้งเตือนเฉพาะสาย ${route.shortName}',
                color: Color(route.colorValue),
                icon: Icons.directions_bus,
                isSelected:
                    _notifyNearBusStop && _selectedNotifyRouteId == route.id,
                onTap: () {
                  setState(() {
                    _notifyNearBusStop = true;
                    _selectedNotifyRouteId = route.id;
                    _hasAlerted = false;
                  });
                  Navigator.pop(context);
                  _showNotificationSnackBar('${route.id} ${route.name}');
                },
              ),
            ),
          ],
        ),
        actions: [
          if (_notifyNearBusStop)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _notifyNearBusStop = false;
                  _selectedNotifyRouteId = null;
                  _hasAlerted = false;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔕 ปิดการแจ้งเตือนรถบัสใกล้'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.grey,
                  ),
                );
              },
              icon: const Icon(Icons.notifications_off, color: Colors.red),
              label: const Text(
                'ปิดการแจ้งเตือน',
                style: TextStyle(color: Colors.red),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
        ],
      ),
    );
  }

  Widget _routeSelectionTile({
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.2),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Colors.green)
          : null,
      onTap: onTap,
      selected: isSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  void _showNotificationSnackBar(String routeName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔔 เปิดการแจ้งเตือน: $routeName (ระยะ 500 เมตร)'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// สร้าง Alert Box แสดงข้อมูลรถที่ติดตาม
  Widget _buildProximityAlertBox() {
    // หารถเป้าหมายตามสายที่เลือก
    Bus? targetBus;
    if (_selectedNotifyRouteId == null) {
      targetBus = _closestBus;
    } else {
      final filtered = _buses
          .where((b) => b.routeId == _selectedNotifyRouteId)
          .toList();
      if (filtered.isNotEmpty) {
        filtered.sort(
          (a, b) => (a.distanceToUser ?? double.infinity).compareTo(
            b.distanceToUser ?? double.infinity,
          ),
        );
        targetBus = filtered.first;
      }
    }

    if (targetBus == null) {
      // ไม่มีรถในสายที่เลือก
      final routeInfo = _selectedNotifyRouteId != null
          ? BusRoute.fromId(_selectedNotifyRouteId!)
          : null;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey, width: 2),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: Colors.grey.shade600, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🔔 กำลังติดตาม: ${routeInfo?.name ?? "ทุกสาย"}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'ยังไม่พบรถในสายนี้',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final routeInfo = BusRoute.fromId(targetBus.routeId);
    final routeColor = routeInfo != null
        ? Color(routeInfo.colorValue)
        : Colors.orange;
    final isNear =
        (targetBus.distanceToUser ?? double.infinity) <= _alertDistanceMeters;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isNear ? Colors.orange.shade100 : routeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNear ? Colors.orange : routeColor,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.directions_bus,
            color: isNear ? Colors.orange : routeColor,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔔 ${_selectedNotifyRouteId != null ? "ติดตาม ${routeInfo?.shortName ?? _selectedNotifyRouteId}" : "ติดตามทุกสาย"}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                Text(
                  '🚌 ${targetBus.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'ระยะห่าง: ${targetBus.distanceToUser?.toStringAsFixed(0) ?? "N/A"} เมตร',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                ),
              ],
            ),
          ),
          if (isNear)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'ใกล้แล้ว!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // BottomBar ที่แก้ให้ใช้ Navigator แบบ Named Route แล้ว
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
            break;
          case 1:
            Navigator.pushReplacementNamed(context, '/busStop');
            break;
          case 2:
            Navigator.pushReplacementNamed(context, '/route');
            break;
          case 3:
            Navigator.pushReplacementNamed(context, '/plan');
            break;
          case 4:
            Navigator.pushReplacementNamed(context, '/feedback');
            break;
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
