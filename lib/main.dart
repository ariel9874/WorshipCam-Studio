import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:io';
import 'package:camera/camera.dart' as cam;
import 'signaling/local_server.dart';
import 'remote_control_screen.dart';
import 'services/camera_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'dart:isolate';

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

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  // WebRTC
  final CameraService _cameraService = CameraService();
  RTCPeerConnection? _peerConnection;
  
  // Servidor Local
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
      await _fetchLocalIp();
      
      _initForegroundTask();
    } catch (e) {
      debugPrint('Error inicializando: $e');
    }
  }

  Future<void> _fetchLocalIp() async {
    String? foundIp;
    try {
      foundIp = await NetworkInfo().getWifiIP();
      if (foundIp == null || foundIp == "127.0.0.1" || foundIp.isEmpty) {
        final interfaces = await NetworkInterface.list();
        
        // Prioridades: 1. USB Tethering, 2. Hotspot Wi-Fi, 3. Wi-Fi Client
        final preferredNames = ['rndis0', 'usb0', 'ap0', 'swlan0', 'wlan0'];
        
        for (var name in preferredNames) {
          for (var interface in interfaces) {
            if (interface.name.toLowerCase().startsWith(name)) {
              for (var addr in interface.addresses) {
                if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
                  foundIp = addr.address;
                  break;
                }
              }
            }
            if (foundIp != null) break;
          }
          if (foundIp != null) break;
        }

        // Fallback: Cualquier interfaz que no sea loopback ni red celular (rmnet)
        if (foundIp == null) {
          for (var interface in interfaces) {
            if (interface.name.toLowerCase().startsWith('rmnet')) continue;
            for (var addr in interface.addresses) {
              if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
                foundIp = addr.address;
                break;
              }
            }
            if (foundIp != null) break;
          }
        }
      }
    } catch (e) {
      debugPrint("Error obteniendo IP: $e");
    }
    
    setState(() {
      _localIp = foundIp ?? "127.0.0.1";
    });
  }

  void _initForegroundTask() {
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
      _peerConnection?.close();
      _peerConnection = null;
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
        final answer = RTCSessionDescription(message['answer']['sdp'], message['answer']['type']);
        await _peerConnection?.setRemoteDescription(answer);
      } else if (type == 'candidate') {
        String candStr = message['candidate']['candidate'] as String;
        
        // ¡LA ESTOCADA FINAL AL BUG DE WEBRTC!
        // Si el PC nos envió su IP oculta en mDNS (.local), la descubrimos nosotros mismos
        // usando la IP real desde donde se conectó al WebSocket, y la inyectamos a la fuerza
        // en el candidato ICE para que WebRTC en Android sepa a quién debe contestar.
        if (candStr.contains('.local')) {
          candStr = candStr.replaceAll(RegExp(r'[a-f0-9\-]+\.local'), clientIp);
          debugPrint("¡Candidato mDNS interceptado! Reemplazado por: \$clientIp");
        }

        final candidate = RTCIceCandidate(
          candStr,
          message['candidate']['sdpMid'],
          message['candidate']['sdpMLineIndex'],
        );
        await _peerConnection?.addCandidate(candidate);
      }
    };

    await _signalingServer!.start();
  }

  Future<void> _startStreaming() async {
    setState(() => _isStreaming = true);

    if (_cameraService.isUsbMode) {
      // En modo USB, la cámara ya genera frames vía onUsbFrame.
      // Solo necesitamos que _isStreaming sea true.
      return;
    }

    if (_cameraService.localStream == null) return;

    final configuration = {
      'iceServers': [] // Vacío para forzar conexión 100% local (offline)
    };

    _peerConnection = await createPeerConnection(configuration);
    _cameraService.peerConnection = _peerConnection;

    _peerConnection!.onIceCandidate = (candidate) {
      String modifiedCandidate = candidate.candidate ?? "";
      
      // Solución para el bug de WebRTC en Android Hotspot:
      // libwebrtc ignora la interfaz ap0 (Hotspot) y solo devuelve 127.0.0.1.
      // Reemplazamos 127.0.0.1 con la IP real del Hotspot para que OBS sepa a dónde enviar.
      if (modifiedCandidate.contains('127.0.0.1') && _localIp != "No conectado a Wi-Fi") {
        modifiedCandidate = modifiedCandidate.replaceAll('127.0.0.1', _localIp);
      }

      _signalingServer!.sendMessageToAll({
        'type': 'candidate',
        'candidate': {
          'candidate': modifiedCandidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        }
      });
    };

    // Añadir tracks usando addTransceiver (Unified Plan)
    if (_cameraService.localStream != null) {
      for (var track in _cameraService.localStream!.getVideoTracks()) {
        await _peerConnection!.addTransceiver(
          track: track,
          init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendOnly,
            streams: [_cameraService.localStream!],
          ),
        );
      }
    }

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": false,
        "OfferToReceiveVideo": false,
      },
      "optional": [],
    };
    final offer = await _peerConnection!.createOffer(offerSdpConstraints);
    
    String modifiedSdp = offer.sdp ?? "";
    if (_localIp != "No conectado a Wi-Fi") {
      modifiedSdp = modifiedSdp.replaceAll('127.0.0.1', _localIp);
      modifiedSdp = modifiedSdp.replaceAll('0.0.0.0', _localIp);
    }
    
    // Forzar un bitrate muy alto para video (15 Mbps)
    final lines = modifiedSdp.split('\r\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('m=video ')) {
        lines.insert(i + 1, 'b=AS:15000');
        break;
      }
    }
    modifiedSdp = lines.join('\r\n');

    await _peerConnection!.setLocalDescription(RTCSessionDescription(modifiedSdp, offer.type));

    _signalingServer!.sendMessageToAll({
      'type': 'offer',
      'offer': {
        'type': offer.type,
        'sdp': modifiedSdp
      }
    });

    setState(() {
      _isStreaming = true;
    });

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

  void _stopStreaming() {
    _peerConnection?.close();
    _peerConnection = null;
    _cameraService.peerConnection = null;
    setState(() {
      _isStreaming = false;
    });

    try {
      FlutterForegroundTask.stopService();
    } catch (e) {
      // Ignorar en test
    }
  }

  @override
  void dispose() {
    _cameraService.dispose();
    _peerConnection?.close();
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
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_cameraService.errorMessage != null || 
        (!_cameraService.isUsbMode && _cameraService.localStream == null) || 
        (_cameraService.isUsbMode && _cameraService.usbCameraController == null)) {
      return Scaffold(
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

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: _cameraService.isUsbMode 
              ? cam.CameraPreview(_cameraService.usbCameraController!)
              : RTCVideoView(
                  _cameraService.localRenderer, 
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
          ),
          
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: _showOBSInstructions,
                            child: _buildStatusChip(
                              Icons.visibility, 
                              _connectedClientsCount > 0 ? "ESPECTADORES: $_connectedClientsCount" : "ESPECTADORES: 0",
                              color: _connectedClientsCount > 0 ? Colors.green : Colors.black54
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Actualizando IP...')));
                              _fetchLocalIp();
                            },
                            child: _buildStatusChip(Icons.refresh, _localIp),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatusChip(
                            Icons.gamepad, 
                            _isRemoteControlConnected ? "CONTROL REMOTO: ON" : "CONTROL REMOTO: OFF",
                            color: _isRemoteControlConnected ? Colors.purpleAccent : Colors.black54
                          ),
                          _buildStatusChip(
                            Icons.high_quality, 
                            "${_cameraService.currentResolution.name.toUpperCase()} @ ${_cameraService.currentFps}fps",
                            color: Colors.blueAccent
                          ),
                        ],
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
                        backgroundColor: _isStreaming ? Colors.green : Colors.redAccent,
                        onPressed: () {
                          if (_isStreaming) {
                            _stopStreaming();
                          } else {
                            _startStreaming();
                          }
                        },
                        child: Icon(_isStreaming ? Icons.stop : Icons.live_tv, color: Colors.white),
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
