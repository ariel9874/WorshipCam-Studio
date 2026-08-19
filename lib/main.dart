import 'dart:io';
import 'package:flutter/material.dart';

import 'ui/mobile/camera_screen.dart';
import 'ui/desktop/remote_control_screen.dart';
import 'services/foreground_task_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CamoCloneApp());
}

class CamoCloneApp extends StatelessWidget {
  const CamoCloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WorshipCam Studio',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueAccent,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: (Platform.isWindows || Platform.isMacOS || Platform.isLinux) 
          ? const RemoteControlScreen() 
          : const CameraScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
    ],
      ),
    );
  }
}
