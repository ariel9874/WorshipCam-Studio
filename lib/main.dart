import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ¡No pedir permisos aquí! El motor Flutter debe iniciar la UI primero.
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
      home: const CameraScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 1. Pedir permisos cuando la pantalla ya está activa
    await [
      Permission.camera,
      Permission.microphone,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    // 2. Obtener cámaras
    try {
      cameras = await availableCameras();
      _initCamera();
    } on CameraException catch (e) {
      debugPrint('Error obteniendo cámaras: $e');
    }
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    
    // Seleccionamos la cámara trasera por defecto
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    // ResolutionPreset.max fuerza la máxima resolución posible (1080p o 4K)
    _controller = CameraController(
      camera,
      ResolutionPreset.max, 
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isReady = true;
        });
      }
    } catch (e) {
      debugPrint("Error inicializando cámara: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text("Iniciando cámara...", style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Visor de Cámara a pantalla completa
          CameraPreview(_controller!),
          
          // Capa de Interfaz de Usuario (UI Overlay)
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Barra Superior (Estados)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatusChip(Icons.wifi, "OBS: Desc"),
                      _buildStatusChip(Icons.bluetooth, "ESP32: OFF"),
                    ],
                  ),
                ),
                
                // Barra Inferior (Controles)
                Container(
                  padding: const EdgeInsets.all(24.0),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white, size: 30),
                        onPressed: () {},
                      ),
                      FloatingActionButton(
                        backgroundColor: Colors.redAccent,
                        onPressed: () {
                          // TODO: Iniciar Transmisión WebRTC a OBS
                        },
                        child: const Icon(Icons.live_tv, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.gamepad, color: Colors.white, size: 30),
                        onPressed: () {
                          // TODO: Abrir panel de control de Motores
                        },
                      ),
                    ],
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatusChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
