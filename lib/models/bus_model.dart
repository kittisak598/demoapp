import 'package:latlong2/latlong.dart';

/// Model สำหรับเก็บข้อมูลรถบัส
class Bus {
  final String id;
  final String name;
  final String routeId; // "S1", "S2", "S3" หรือ "unknown"
  final LatLng position;
  double? distanceToUser; // ระยะห่างจากผู้ใช้ (เมตร)

  Bus({
    required this.id,
    required this.name,
    required this.routeId,
    required this.position,
    this.distanceToUser,
  });

  /// สร้างจาก Firebase snapshot
  factory Bus.fromFirebase(String id, Map<dynamic, dynamic> data) {
    // พยายามดึง routeId จากหลายแหล่ง:
    // 1. field "route" หรือ "routeId" โดยตรง
    // 2. วิเคราะห์จาก id (เช่น "S1_bus1" -> "S1")
    // 3. วิเคราะห์จาก name (เช่น "สาย S1 หน้ามอ" -> "S1")
    String routeId = _extractRouteId(id, data);

    return Bus(
      id: id,
      name: data['name']?.toString() ?? 'สาย $id',
      routeId: routeId,
      position: LatLng(
        double.parse(data['lat'].toString()),
        double.parse(data['lng'].toString()),
      ),
    );
  }

  /// ดึง routeId จากข้อมูล
  static String _extractRouteId(String id, Map<dynamic, dynamic> data) {
    // 1. ลองดึงจาก field route/routeId
    if (data.containsKey('route')) {
      return data['route'].toString().toUpperCase();
    }
    if (data.containsKey('routeId')) {
      return data['routeId'].toString().toUpperCase();
    }

    // 2. วิเคราะห์จาก id (เช่น "S1_bus1", "s1-001")
    final idUpper = id.toUpperCase();
    if (idUpper.contains('S1') ||
        idUpper.contains('NAMOR') ||
        idUpper.contains('หน้ามอ')) {
      return 'S1';
    }
    if (idUpper.contains('S2') ||
        idUpper.contains('HORNAI') ||
        idUpper.contains('หอใน')) {
      return 'S2';
    }
    if (idUpper.contains('S3') || idUpper.contains('ICT')) {
      return 'S3';
    }

    // 3. วิเคราะห์จาก name
    final name = data['name']?.toString().toUpperCase() ?? '';
    if (name.contains('S1') ||
        name.contains('หน้ามอ') ||
        name.contains('PKY')) {
      return 'S1';
    }
    if (name.contains('S2') || name.contains('หอใน')) {
      return 'S2';
    }
    if (name.contains('S3') || name.contains('ICT')) {
      return 'S3';
    }

    return 'UNKNOWN';
  }

  /// Copy with distance
  Bus copyWithDistance(double distance) {
    return Bus(
      id: id,
      name: name,
      routeId: routeId,
      position: position,
      distanceToUser: distance,
    );
  }
}

/// ข้อมูลสายรถสำหรับ UI
class BusRoute {
  final String id;
  final String name;
  final String shortName;
  final int colorValue;

  const BusRoute({
    required this.id,
    required this.name,
    required this.shortName,
    required this.colorValue,
  });

  /// สายรถทั้งหมดในระบบ
  static const List<BusRoute> allRoutes = [
    BusRoute(
      id: 'S1',
      name: 'หน้ามอ-PKY',
      shortName: 'หน้ามอ',
      colorValue: 0xFF44B678,
    ),
    BusRoute(id: 'S2', name: 'หอใน', shortName: 'หอใน', colorValue: 0xFFFF3859),
    BusRoute(id: 'S3', name: 'ICT', shortName: 'ICT', colorValue: 0xFF1177FC),
  ];

  /// หาสายจาก id
  static BusRoute? fromId(String id) {
    try {
      return allRoutes.firstWhere((r) => r.id == id.toUpperCase());
    } catch (_) {
      return null;
    }
  }
}
