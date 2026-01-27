import 'package:flutter/material.dart';
// --- [1] เพิ่ม import ของ Firebase ---
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // ไฟล์นี้ถูกสร้างขึ้นตอนทำ flutterfire configure
// -----------------------------------

import 'package:projectapp/busstop-page.dart';
import 'package:projectapp/feedback-page.dart';
import 'package:projectapp/route-page.dart';
import 'package:projectapp/upbus-page.dart';
import 'package:projectapp/plan-page.dart';

// --- [2] แก้ไขฟังก์ชัน main ---
void main() async {
  // ต้องเติม async
  // ต้องมีบรรทัดนี้ เพื่อให้ Flutter พร้อมทำงานก่อนเริ่ม Firebase
  WidgetsFlutterBinding.ensureInitialized();

  // คำสั่งเชื่อมต่อ Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}
// -----------------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UP BUS',
      theme: ThemeData(
        primaryColor: const Color(0xFF9C27B0),
        useMaterial3: false,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const UpBusHomePage(), // ส่วนที่ 1
        '/busStop': (context) => const BusStopPage(), // ส่วนที่ 2
        '/route': (context) => const RoutePage(), // ส่วนที่ 3
        '/plan': (context) => const PlanPage(),
        '/feedback': (context) => const FeedbackPage(), // ส่วนที่ 4
      },
    );
  }
}
