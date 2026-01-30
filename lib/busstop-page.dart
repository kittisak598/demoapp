import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

enum BusLine { yellow, red, blue }

class BusStopPage extends StatefulWidget {
  const BusStopPage({super.key});

  @override
  State<BusStopPage> createState() => _BusStopPageState();
}

class _BusStopPageState extends State<BusStopPage> {
  BusLine _selectedLine = BusLine.red;

  // 0=Live, 1=Stop(หน้านี้), 2=Route, 3=Plan, 4=Feed
  int _selectedBottomIndex = 1;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String get _lineTitle {
    switch (_selectedLine) {
      case BusLine.yellow:
        return 'Yellow Line : สายสีเหลือง';
      case BusLine.red:
        return 'Red Line : สายสีแดง';
      case BusLine.blue:
        return 'Blue Line : สายสีน้ำเงิน';
    }
  }

  Color get _lineColor {
    switch (_selectedLine) {
      case BusLine.yellow:
        return Colors.yellow.shade600;
      case BusLine.red:
        return Colors.red.shade600;
      case BusLine.blue:
        return Colors.blue.shade700;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSelectLine(BusLine line) {
    setState(() => _selectedLine = line);
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Search ---
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'ค้นหาชื่อป้าย...',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // --- List รายการ ---
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          color: _lineColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Text(
                            _lineTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            color: const Color(0xFFEEEEEE),
                            child: StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('Bus stop')
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (snapshot.hasError)
                                  return const Center(
                                    child: Text('เกิดข้อผิดพลาด'),
                                  );
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting)
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                if (!snapshot.hasData ||
                                    snapshot.data!.docs.isEmpty)
                                  return const Center(
                                    child: Text('ไม่พบข้อมูล'),
                                  );

                                var documents = snapshot.data!.docs;
                                if (_searchQuery.isNotEmpty) {
                                  documents = documents.where((doc) {
                                    var data =
                                        doc.data() as Map<String, dynamic>;
                                    return (data['name'] ?? '')
                                        .toLowerCase()
                                        .contains(_searchQuery.toLowerCase());
                                  }).toList();
                                }

                                return ListView.separated(
                                  itemCount: documents.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    height: 1,
                                    color: Colors.white,
                                  ),
                                  itemBuilder: (context, index) {
                                    var data =
                                        documents[index].data()
                                            as Map<String, dynamic>;
                                    return ListTile(
                                      tileColor: Colors.grey.shade300,
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.white,
                                        child: Text(
                                          data['stop_id']?.toString() ?? '-',
                                          style: TextStyle(
                                            color: _lineColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        data['name'] ?? 'ป้ายไร้ชื่อ',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        "พิกัด: ${data['lat'] ?? '-'}, ${data['long'] ?? '-'}",
                                      ),
                                      trailing: const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16,
                                        color: Colors.grey,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
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

  // --- Widgets ย่อย ---

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
            'BUS STOP',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
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

  Widget _lineCircle(Color c, bool sel, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: sel ? Border.all(color: Colors.black, width: 3) : null,
        ),
      ),
    );
  }

  // --- [แก้ไข] ส่วน Bottom Bar ใหม่ ---
  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF9C27B0),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(15),
          topRight: Radius.circular(15),
        ),
      ),
      // ลด Padding แนวนอนลงนิดหน่อย เพื่อให้ spaceEvenly ทำงานได้สวยขึ้น
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: SizedBox(
        height: 70,
        child: Row(
          // ใช้ spaceEvenly เพื่อกระจายปุ่มให้ห่างเท่าๆ กัน และไม่ชิดขอบจอ
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _bottomNavItem(0, Icons.location_on, 'Live'),
            _bottomNavItem(1, Icons.directions_bus, 'Stop'), // หน้านี้
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
            Navigator.pushReplacementNamed(context, '/');
            break;
          case 1:
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
        // เอาพื้นหลังสีขาวออก เพื่อลดความแออัด (หรือจะใส่กลับถ้าชอบก็ได้ครับ)
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
