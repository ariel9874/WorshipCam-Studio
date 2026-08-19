import 'dart:io';
import 'package:flutter/foundation.dart';

class AdbService {
  static String get _adbCommand {
    String adbCommand = 'adb';
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        final adbPath = '$localAppData\\Android\\Sdk\\platform-tools\\adb.exe';
        if (File(adbPath).existsSync()) {
          adbCommand = adbPath;
        }
      }
    }
    return adbCommand;
  }

  static Future<bool> setupUSBTunnel() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        debugPrint("Iniciando túnel USB ADB...");
        final result = await Process.run(_adbCommand, ['forward', 'tcp:8080', 'tcp:8080']);
        if (result.exitCode == 0) {
          debugPrint("Túnel USB establecido.");
          return true;
        } else {
          debugPrint("Fallo al establecer túnel ADB: ${result.stderr}");
          return false;
        }
      } catch (e) {
        debugPrint("Error ejecutando adb: $e");
        return false;
      }
    }
    return false;
  }

  static Future<void> removeUSBTunnel() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        await Process.run(_adbCommand, ['forward', '--remove', 'tcp:8080']);
      } catch (e) {
        debugPrint("Error removiendo túnel ADB: $e");
      }
    }
  }
}
