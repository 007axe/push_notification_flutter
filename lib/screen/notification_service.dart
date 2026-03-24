import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:flutter_project_for_notifications/firebase_options.dart';
import 'package:push_msg_service/firebase_options.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Stream controller for notification tap events
  static final StreamController<RemoteMessage> onNotificationTap =
      StreamController<RemoteMessage>.broadcast();

  // FCM Token
  static String? _fcmToken;

  /// Get current FCM token
  static String? get fcmToken => _fcmToken;

  // handles messages when the app is in the background or terminated.
  @pragma('vm:entry-point')
  static Future<void> firebaseMessagingBackgroundHandler(
    RemoteMessage message,
  ) async {
    // Firebase must be initialized in background isolate
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize local notification plugin and show notification
    await _initializeLocalNotification();
    await _showFlutterNotification(message);
  }

  /// Initializes Firebase Messaging and Local Notifications
  /// Note: Call FirebaseMessaging.onBackgroundMessage() from main.dart before runApp()
  static Future<void> initializeNotification() async {
    // 1. Request permissions (required on iOS, optional on Android)
    await _requestPermissions();

    // 2. Initialize local notification
    await _initializeLocalNotification();

    // 3. Get and monitor FCM token
    await _initFCMToken();

    // 5. Setup foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("Received message in foreground: ${message.messageId}");
      _showFlutterNotification(message);
    });

    // 6. Setup background message tap handler (app in background, not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("Notification tapped from background: ${message.data}");
      onNotificationTap.add(message);
    });

    // 7. Check for initial notification (app launched from terminated state)
    await _getInitialNotification();
  }

  /// Request notification permissions
  static Future<void> _requestPermissions() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    print(
      'User notification permission status: ${settings.authorizationStatus}',
    );

    // For iOS, also request local notification permissions
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // For Android 13+, request exact alarm permission if needed
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  /// Initialize and monitor FCM token
  static Future<void> _initFCMToken() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Get initial token
    try {
      _fcmToken = await messaging.getToken();
      print("FCM Token: $_fcmToken");
    } catch (e) {
      print("Error getting FCM token: $e");
    }

    // Listen for token refresh
    messaging.onTokenRefresh.listen((String token) {
      _fcmToken = token;
      print("FCM Token refreshed: $token");
      // Here you would typically send the new token to your server
    });
  }

  /// Get FCM token (public method)
  static Future<String?> getToken() async {
    try {
      _fcmToken = await FirebaseMessaging.instance.getToken();
      return _fcmToken;
    } catch (e) {
      print("Error getting FCM token: $e");
      return null;
    }
  }

  /// Delete FCM token (useful for logout)
  static Future<void> deleteToken() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
      _fcmToken = null;
      print("FCM Token deleted");
    } catch (e) {
      print("Error deleting FCM token: $e");
    }
  }

  /// Subscribe to a topic
  static Future<void> subscribeToTopic(String topic) async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      print("Subscribed to topic: $topic");
    } catch (e) {
      print("Error subscribing to topic: $e");
    }
  }

  /// Unsubscribe from a topic
  static Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      print("Unsubscribed from topic: $topic");
    } catch (e) {
      print("Error unsubscribing from topic: $e");
    }
  }

  /// Show a local notification when a message is received
  static Future<void> _showFlutterNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    Map<String, dynamic>? data = message.data;

    String title = notification?.title ?? data['title'] ?? 'No Title';
    String body = notification?.body ?? data['body'] ?? 'No Body';

    // Android notification config
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'CHANNEL_ID',
      'CHANNEL_NAME',
      channelDescription: 'Notification channel for basic tests',
      priority: Priority.high,
      importance: Importance.high,
    );

    // ios notification config
    DarwinNotificationDetails iOSDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    // Combine platform-specific setting
    NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    // Show notification with unique ID based on timestamp
    await flutterLocalNotificationsPlugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: message.data.toString(),
    );
  }

  /// Initializes the local notification system (both Android and iOS)
  static Future<void> _initializeLocalNotification() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iOSInit = DarwinInitializationSettings();

    final InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iOSInit,
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print("User tapped notification: ${response.payload}");
        // You can parse the payload and handle navigation here
      },
    );
  }

  /// Handles notification tap when app is terminated
  static Future<void> _getInitialNotification() async {
    RemoteMessage? message = await FirebaseMessaging.instance
        .getInitialMessage();

    if (message != null) {
      print(
        "App launched from terminated state via notification: ${message.data}",
      );
      // Add to stream so app can handle it
      onNotificationTap.add(message);
    }
  }

  /// Dispose stream controller (call this in app's dispose)
  static void dispose() {
    onNotificationTap.close();
  }
}
