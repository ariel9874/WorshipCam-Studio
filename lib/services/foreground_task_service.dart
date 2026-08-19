import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class ForegroundTaskService {
  static void init() {
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'worshipcam_service',
          channelName: 'Transmisión en Segundo Plano',
          channelDescription: 'Mantiene activa la transmisión de video cuando la pantalla se apaga.',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: true,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
    } catch (e) {
      debugPrint("Error init ForegroundTask: $e");
    }
  }

  static Future<void> start() async {
    try {
      if (await FlutterForegroundTask.isRunningService == false) {
        FlutterForegroundTask.startService(
          notificationTitle: 'Transmitiendo a OBS...',
          notificationText: 'WorshipCam está ejecutándose en segundo plano.',
          callback: startCallback,
        );
      }
    } catch (e) {
      debugPrint("ForegroundTask no iniciado en entorno de pruebas: $e");
    }
  }

  static Future<void> stop() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint("Error deteniendo ForegroundTask: $e");
    }
  }
}
