import Flutter
import UIKit
import GoogleMaps
import Firebase
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps API Key for BMS Pro Pink
    GMSServices.provideAPIKey("AIzaSyA2LP8ornek2rve4QBm5d9FLQKOrF78I6M")
    
    // Configure Firebase FIRST
    FirebaseApp.configure()
    
    // Set up push notifications delegate BEFORE registering
    UNUserNotificationCenter.current().delegate = self
    
    // Set Firebase Messaging delegate
    Messaging.messaging().delegate = self
    
    // Request notification permission
    let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
    UNUserNotificationCenter.current().requestAuthorization(
      options: authOptions,
      completionHandler: { granted, error in
        print("📱 Notification permission granted: \(granted)")
        if let error = error {
          print("❌ Notification permission error: \(error)")
        }
      }
    )
    
    // Register for remote notifications
    application.registerForRemoteNotifications()
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Handle APNs token registration - CRITICAL for push notifications
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    print("📱 APNs device token received: \(deviceToken.map { String(format: "%02.2hhx", $0) }.joined())")
    
    // Pass device token to Firebase
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
  
  // Handle failed registration
  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Failed to register for remote notifications: \(error)")
  }
  
  // CRITICAL: Handle background/terminated notifications - THIS WAS MISSING!
  override func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    print("📩 Background notification received!")
    print("📩 UserInfo: \(userInfo)")
    
    // Let Firebase Messaging handle the message
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    // Process the notification data
    if let aps = userInfo["aps"] as? [String: Any] {
      print("📩 APS payload: \(aps)")
    }
    
    // MUST call completion handler
    completionHandler(.newData)
  }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("🔥 Firebase FCM token: \(String(describing: fcmToken))")
    
    let dataDict: [String: String] = ["token": fcmToken ?? ""]
    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: dataDict
    )
  }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate {
  // Handle notification when app is in foreground
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    print("📩 Foreground notification received: \(userInfo)")
    
    // Let Firebase handle the message
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    // Show notification banner even when app is in foreground
    completionHandler([[.banner, .badge, .sound]])
  }
  
  // Handle notification tap
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    print("📩 Notification tapped: \(userInfo)")
    
    // Let Firebase handle the message
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    completionHandler()
  }
}
