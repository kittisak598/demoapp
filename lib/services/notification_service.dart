import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

/// Service สำหรับจัดการ Push Notification และ Vibration
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Initialize notification service
  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);
    _initialized = true;
  }

  /// แสดง Push Notification เมื่อรถบัสใกล้
  static Future<void> showBusNearbyNotification({
    required String busName,
    required double distanceMeters,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'bus_proximity_channel',
      'Bus Proximity Alerts',
      channelDescription: 'แจ้งเตือนเมื่อรถบัสเข้าใกล้',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      1,
      '🚌 รถบัสใกล้ถึงแล้ว!',
      '$busName อยู่ห่าง ${distanceMeters.toStringAsFixed(0)} เมตร',
      details,
    );
  }

  /// สั่นเตือน
  static Future<void> vibrate() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      await Vibration.vibrate(duration: 500, amplitude: 128);
    }
  }

  /// แจ้งเตือนพร้อมสั่น
  static Future<void> alertBusNearby({
    required String busName,
    required double distanceMeters,
  }) async {
    await Future.wait([
      showBusNearbyNotification(
        busName: busName,
        distanceMeters: distanceMeters,
      ),
      vibrate(),
    ]);
  }
}
