import UIKit
import Flutter
import GoogleMaps // 1. เพิ่มบรรทัดนี้

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 2. เพิ่มบรรทัดนี้ (ใส่ Key ของคุณ)
    GMSServices.provideAPIKey("AIzaSyD2OjFTwh3uBlTZmm3pQ8P0J5O2Yg7wQyU")
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}