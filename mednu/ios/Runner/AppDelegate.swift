import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Shared with the mednu_doctor app's key — must have this app's iOS
    // bundle id added to that key's allowed apps in Google Cloud Console.
    GMSServices.provideAPIKey("AIzaSyBTt8cnzrKMOxMJpAnFgTiZxJSaqxE3aj8")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
