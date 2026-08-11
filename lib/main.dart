import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

List<CameraDescription> cameras = [];

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
  CameraDescription? _selectedCamera;
  bool _isReady = false;
  bool _isFocusLocked = false;

  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  
  double _currentExposure = 0.0;
  double _minExposure = 0.0;
  double _maxExposure = 0.0;
  
  ResolutionPreset _currentResolution = ResolutionPreset.veryHigh;
  int _currentFps = 30;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    try {
      cameras = await availableCameras();
      _initCamera();
    } on CameraException catch (e) {
      debugPrint('Error obteniendo cámaras: $e');
    }
  }

  Future<void> _initCamera([CameraDescription? camera]) async {
    if (cameras.isEmpty) return;
    
    // Si hay un controlador anterior, lo descartamos
    await _controller?.dispose();
    
    // Elegir cámara proporcionada, o la primera trasera por defecto
    _selectedCamera = camera ?? cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      _selectedCamera!,
      _currentResolution, 
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      
      _minZoom = await _controller!.getMinZoomLevel();
      _maxZoom = await _controller!.getMaxZoomLevel();
      _minExposure = await _controller!.getMinExposureOffset();
      _maxExposure = await _controller!.getMaxExposureOffset();
      
      // Reiniciamos variables de UI
      _currentZoom = 1.0;
      _currentExposure = 0.0;
      _isFocusLocked = false;

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

  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Ajustes de Cámara", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  // LENTE (SELECCIÓN DE CÁMARA MULTIPLE)
                  Row(
                    children: [
                      const Icon(Icons.camera_alt, color: Colors.white),
                      const SizedBox(width: 10),
                      const Text("Lente:", style: TextStyle(color: Colors.white)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButton<CameraDescription>(
                          dropdownColor: Colors.black87,
                          isExpanded: true,
                          value: _selectedCamera,
                          style: const TextStyle(color: Colors.white),
                          items: cameras.map((c) {
                            // En Android los nombres suelen ser 0, 1, 2, 3
                            String lensName = "Lente ${c.name} (${c.lensDirection.name})";
                            return DropdownMenuItem(
                              value: c,
                              child: Text(lensName, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (newCamera) async {
                            if (newCamera != null && newCamera != _selectedCamera) {
                              Navigator.pop(context); // Cerramos el panel
                              setState(() {
                                _isReady = false; // Pantalla de carga
                              });
                              await _initCamera(newCamera); // Cargamos nuevo lente
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  // Calidad de Video (Resolución)
                  Row(
                    children: [
                      const Icon(Icons.hd, color: Colors.white),
                      const SizedBox(width: 10),
                      const Text("Calidad:", style: TextStyle(color: Colors.white)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButton<ResolutionPreset>(
                          dropdownColor: Colors.black87,
                          isExpanded: true,
                          value: _currentResolution,
                          style: const TextStyle(color: Colors.white),
                          items: ResolutionPreset.values.map((preset) {
                            return DropdownMenuItem(
                              value: preset,
                              child: Text(preset.name.toUpperCase()),
                            );
                          }).toList(),
                          onChanged: (newPreset) async {
                            if (newPreset != null && newPreset != _currentResolution) {
                              Navigator.pop(context);
                              setState(() {
                                _currentResolution = newPreset;
                                _isReady = false;
                              });
                              await _initCamera(_selectedCamera);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Velocidad (FPS) - Se aplicará en el motor WebRTC
                  Row(
                    children: [
                      const Icon(Icons.speed, color: Colors.white),
                      const SizedBox(width: 10),
                      const Text("FPS:", style: TextStyle(color: Colors.white)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButton<int>(
                          dropdownColor: Colors.black87,
                          isExpanded: true,
                          value: _currentFps,
                          style: const TextStyle(color: Colors.white),
                          items: [24, 30, 60].map((fps) {
                            return DropdownMenuItem(
                              value: fps,
                              child: Text("$fps FPS"),
                            );
                          }).toList(),
                          onChanged: (newFps) {
                            if (newFps != null) {
                              setModalState(() {
                                _currentFps = newFps;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  // Slider de Zoom
                  Row(
                    children: [
                      const Icon(Icons.zoom_in, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Slider(
                          value: _currentZoom,
                          min: _minZoom,
                          max: _maxZoom,
                          activeColor: Colors.blueAccent,
                          onChanged: (value) async {
                            setModalState(() => _currentZoom = value);
                            await _controller?.setZoomLevel(value);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 40, 
                        child: Text("${_currentZoom.toStringAsFixed(1)}x", style: const TextStyle(color: Colors.white))
                      ),
                    ],
                  ),
                  
                  // Slider de Exposición (Brillo)
                  Row(
                    children: [
                      const Icon(Icons.brightness_6, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Slider(
                          value: _currentExposure,
                          min: _minExposure,
                          max: _maxExposure,
                          activeColor: Colors.amber,
                          onChanged: (value) async {
                            setModalState(() => _currentExposure = value);
                            await _controller?.setExposureOffset(value);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          "${_currentExposure > 0 ? '+' : ''}${_currentExposure.toStringAsFixed(1)}",
                          style: const TextStyle(color: Colors.white)
                        ),
                      ),
                    ],
                  ),
                  
                  // Toggle Enfoque
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.center_focus_strong, color: Colors.white),
                          SizedBox(width: 10),
                          Text("Bloquear Enfoque", style: TextStyle(color: Colors.white)),
                        ],
                      ),
                      Switch(
                        value: _isFocusLocked,
                        activeColor: Colors.redAccent,
                        onChanged: (value) async {
                          setState(() {
                            _isFocusLocked = value;
                          });
                          setModalState(() {});
                          await _controller?.setFocusMode(
                            value ? FocusMode.locked : FocusMode.auto,
                          );
                        },
                      )
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = 1 / (_controller!.value.aspectRatio * constraints.maxHeight / constraints.maxWidth);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  if (_controller == null || _isFocusLocked) return;
                  final x = details.localPosition.dx / constraints.maxWidth;
                  final y = details.localPosition.dy / constraints.maxHeight;
                  _controller!.setFocusPoint(Offset(x, y));
                },
                child: Center(
                  child: AspectRatio(
                    // Flutter en vertical requiere invertir el aspect ratio
                    aspectRatio: 1 / _controller!.value.aspectRatio,
                    child: CameraPreview(_controller!),
                  ),
                ),
              );
            }
          ),
          
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatusChip(Icons.wifi, "OBS: Desc"),
                      _buildStatusChip(
                        _isFocusLocked ? Icons.lock : Icons.center_focus_weak, 
                        _isFocusLocked ? "Enfoque: FIJO" : "Enfoque: AUTO",
                        color: _isFocusLocked ? Colors.redAccent : Colors.black54
                      ),
                    ],
                  ),
                ),
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
                        onPressed: _showSettingsPanel,
                      ),
                      FloatingActionButton(
                        backgroundColor: Colors.redAccent,
                        onPressed: () {},
                        child: const Icon(Icons.live_tv, color: Colors.white),
                      ),
                      IconButton(
                        icon: const Icon(Icons.gamepad, color: Colors.white, size: 30),
                        onPressed: () {},
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

  Widget _buildStatusChip(IconData icon, String text, {Color color = Colors.black54}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
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
