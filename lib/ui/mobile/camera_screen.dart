import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:camera/camera.dart' as cam;
import 'package:permission_handler/permission_handler.dart';

import '../../services/camera_service.dart';
import '../../signaling/local_server.dart';
import '../../utils/network_utils.dart';
import '../../services/foreground_task_service.dart';
import '../../services/webrtc_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final CameraService _cameraService = CameraService();
  final WebRTCService _webRTCService = WebRTCService();
  LocalSignalingServer? _signalingServer;
  
  String _localIp = "Obteniendo IP...";
  bool _isStreaming = false;
  int _connectedClientsCount = 0;
  bool _isRemoteControlConnected = false;
  
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
      _cameraService.addListener(() {
        if (mounted) setState(() {});
      });
      _cameraService.onUsbFrame = (bytes) {
        if (_isStreaming && _signalingServer != null) {
          _signalingServer!.broadcastVideoFrame(bytes);
        }
      };
      await _cameraService.initialize();
      await _initSignalingServer();
      
      final ip = await NetworkUtils.fetchLocalIp();
      if (mounted) setState(() => _localIp = ip);
      
      ForegroundTaskService.init();
    } catch (e) {
      debugPrint('Error inicializando: $e');
    }
  }

  Future<void> _initSignalingServer() async {
    _signalingServer = LocalSignalingServer();
    
    _signalingServer!.onClientConnected = (clientId) {
      setState(() => _connectedClientsCount = 1);
      if (_isStreaming) {
        if (!_cameraService.isUsbMode) {
          _startStreaming();
        }
      }
    };
    
    _signalingServer!.onClientDisconnected = (clientId) {
      setState(() => _connectedClientsCount = 0);
      _webRTCService.stopConnection();
      _cameraService.peerConnection = null;
    };
    
    _signalingServer!.onRemoteControlStatusChanged = (connected) {
      setState(() => _isRemoteControlConnected = connected);
    };

    _signalingServer!.onRemoteCommandReceived = (message) async {
      final type = message['type'];
      if (type == 'switch_lens') {
        _cameraService.switchLens();
      } else if (type == 'toggle_flash') {
        _cameraService.toggleFlash();
      } else if (type == 'set_resolution') {
        final val = message['value'];
        ResolutionPreset preset = ResolutionPreset.veryHigh;
        if (val == 'high') preset = ResolutionPreset.high;
        if (val == 'max') preset = ResolutionPreset.max;
        _cameraService.setResolution(preset);
      } else if (type == 'set_fps') {
        final fps = (message['value'] is int) ? message['value'] : int.tryParse(message['value'].toString()) ?? 30;
        _cameraService.setFps(fps);
      }
    };

    _signalingServer!.onMessageReceived = (clientId, clientIp, message) async {
      final type = message['type'];
      if (type == 'answer') {
        await _webRTCService.handleAnswer(message['answer']);
      } else if (type == 'candidate') {
        await _webRTCService.handleCandidate(message['candidate'], clientIp);
      }
    };

    await _signalingServer!.start();
  }

  Future<void> _startStreaming() async {
    setState(() => _isStreaming = true);

    if (_cameraService.isUsbMode) {
      return;
    }

    if (_cameraService.localStream == null) return;

    await _webRTCService.startConnection(
      localStream: _cameraService.localStream!,
      localIp: _localIp,
      onSendMessage: (msg) => _signalingServer!.sendMessageToAll(msg),
    );
    
    _cameraService.peerConnection = _webRTCService.peerConnection;

    setState(() {
      _isStreaming = true;
    });

    ForegroundTaskService.start();
  }

  void _stopStreaming() {
    _webRTCService.stopConnection();
    _cameraService.peerConnection = null;
    setState(() {
      _isStreaming = false;
    });
    ForegroundTaskService.stop();
  }

  @override
  void dispose() {
    _cameraService.dispose();
    _webRTCService.stopConnection();
    super.dispose();
  }

  void _showOBSInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text("Conectar a OBS", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("1. Abre OBS Studio en tu PC.", style: TextStyle(color: Colors.white)),
            const SizedBox(height: 10),
            const Text("2. Agrega una nueva fuente de tipo 'Navegador' (Browser Source).", style: TextStyle(color: Colors.white)),
            const SizedBox(height: 10),
            const Text("3. Desmarca 'Archivo Local' y pon esta URL:", style: TextStyle(color: Colors.white)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.black,
              child: SelectableText("http://$_localIp:8080", style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            const Text("4. ¡El video aparecerá automáticamente con latencia cero!", style: TextStyle(color: Colors.white)),
            const SizedBox(height: 10),
            const Text("Si usas cable USB, abre CMD y usa 'adb reverse tcp:8080 tcp:8080' y la URL será http://localhost:8080", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ENTENDIDO", style: TextStyle(color: Colors.blueAccent)),
          )
        ],
      ),
    );
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
                  const Text("CONFIGURACIÓN DE CÁMARA", style: TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 10),

                  // Toggle de Modo Wi-Fi / USB
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Modo Conexión:", style: TextStyle(color: Colors.white, fontSize: 16)),
                      ToggleButtons(
                        isSelected: [!_cameraService.isUsbMode, _cameraService.isUsbMode],
                        onPressed: (index) {
                          _cameraService.setTransmissionMode(index == 1);
                        },
                        color: Colors.white54,
                        selectedColor: Colors.white,
                        fillColor: Colors.blueAccent.withOpacity(0.3),
                        borderColor: Colors.white24,
                        selectedBorderColor: Colors.blueAccent,
                        borderRadius: BorderRadius.circular(8),
                        children: const [
                          Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("Wi-Fi (WebRTC)")),
                          Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("USB (MJPEG)")),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Lente
                  Row(  children: [
                      const Icon(Icons.camera_alt, color: Colors.white),
                      const SizedBox(width: 10),
                      const Text("Lente:", style: TextStyle(color: Colors.white)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButton<MediaDeviceInfo>(
                          dropdownColor: Colors.black87,
                          isExpanded: true,
                          value: _cameraService.selectedCamera,
                          style: const TextStyle(color: Colors.white),
                          items: _cameraService.cameras.map((c) {
                            return DropdownMenuItem(
                              value: c,
                              child: Text(c.label.isNotEmpty ? c.label : "Cámara ${c.deviceId}", overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (newCamera) {
                            if (newCamera != null && newCamera != _cameraService.selectedCamera) {
                              Navigator.pop(context);
                              _cameraService.startCamera(newCamera);
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
                          value: _cameraService.currentResolution,
                          style: const TextStyle(color: Colors.white),
                          items: ResolutionPreset.values.map((preset) {
                            return DropdownMenuItem(
                              value: preset,
                              child: Text(preset.name.toUpperCase()),
                            );
                          }).toList(),
                          onChanged: (newPreset) {
                            if (newPreset != null && newPreset != _cameraService.currentResolution) {
                              Navigator.pop(context);
                              _cameraService.setResolution(newPreset);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Velocidad (FPS)
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
                          value: _cameraService.currentFps,
                          style: const TextStyle(color: Colors.white),
                          items: [24, 30, 60].map((fps) {
                            return DropdownMenuItem(
                              value: fps,
                              child: Text("$fps FPS"),
                            );
                          }).toList(),
                          onChanged: (newFps) {
                            if (newFps != null && newFps != _cameraService.currentFps) {
                              Navigator.pop(context);
                              _cameraService.setFps(newFps);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text("NOTA: Zoom y Exposición Manual están deshabilitados en modo WebRTC para priorizar latencia cero y aceleración de hardware.", 
                             style: TextStyle(color: Colors.amber, fontSize: 12), textAlign: TextAlign.center),
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
    if (!_cameraService.isReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_cameraService.errorMessage != null || 
        (!_cameraService.isUsbMode && _cameraService.localStream == null) || 
        (_cameraService.isUsbMode && _cameraService.usbCameraController == null)) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 60),
                const SizedBox(height: 20),
                Text(_cameraService.errorMessage ?? "Error desconocido al acceder a la cámara.", 
                     textAlign: TextAlign.center, 
                     style: const TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    _cameraService.setTransmissionMode(_cameraService.isUsbMode);
                  },
                  child: const Text("Reintentar"),
                )
              ],
            ),
          ),
        ),
      );
    }

    bool isConnected = _connectedClientsCount > 0 || _isRemoteControlConnected;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Vista de cámara (oculta o muy oscurecida si está conectado)
          Opacity(
            opacity: isConnected ? 0.3 : 1.0,
            child: _cameraService.isUsbMode 
              ? cam.CameraPreview(_cameraService.usbCameraController!)
              : RTCVideoView(
                  _cameraService.localRenderer, 
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
          ),
          
          if (isConnected)
            // UI Minimalista (Tally Light)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.6),
                          blurRadius: 30,
                          spreadRadius: 10,
                        )
                      ]
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text("EN VIVO", style: TextStyle(color: Colors.redAccent, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 10),
                  const Text("Controlado desde Windows", style: TextStyle(color: Colors.white54, fontSize: 14)),
                  const SizedBox(height: 50),
                  TextButton.icon(
                    onPressed: () {
                      // Desconectar forzosamente para mostrar la UI completa
                      _signalingServer?.sendMessageToAll({'type': 'disconnect'});
                      setState(() {
                        _connectedClientsCount = 0;
                        _isRemoteControlConnected = false;
                      });
                    },
                    icon: const Icon(Icons.lock_open, color: Colors.white70),
                    label: const Text("Forzar Desbloqueo", style: TextStyle(color: Colors.white70)),
                  )
                ],
              ),
            )
          else
            // UI Completa (Modo Standby)
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: _showOBSInstructions,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(color: Colors.blueAccent)
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.qr_code, color: Colors.blueAccent),
                                    const SizedBox(width: 10),
                                    Text("IP: $_localIp", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text("Esperando conexión de OBS o Panel de Control...", 
                          style: TextStyle(color: Colors.white70), 
                          textAlign: TextAlign.center
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
                         colors: [Colors.black, Colors.transparent],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white70, size: 30),
                          onPressed: _showSettingsPanel,
                          tooltip: "Ajustes Manuales",
                        ),
                        FloatingActionButton.extended(
                          backgroundColor: _isStreaming ? Colors.green : Colors.white24,
                          onPressed: () {
                            if (_isStreaming) {
                              _stopStreaming();
                            } else {
                              _startStreaming();
                            }
                          },
                          icon: Icon(_isStreaming ? Icons.stop : Icons.power_settings_new, color: Colors.white),
                          label: Text(_isStreaming ? "DETENER" : "INICIAR SERVIDOR", style: const TextStyle(color: Colors.white)),
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
