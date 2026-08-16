import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:io' show Platform;
import 'signaling/local_server.dart';
import 'remote_control_screen.dart';

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

enum ResolutionPreset { low, medium, high, veryHigh, ultraHigh, max }

class _CameraScreenState extends State<CameraScreen> {
  // WebRTC
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  RTCPeerConnection? _peerConnection;
  
  // Servidor Local
  LocalSignalingServer? _signalingServer;
  String _localIp = "Obteniendo IP...";
  bool _isStreaming = false;
  int _connectedClientsCount = 0;
  bool _isRemoteControlConnected = false;
  
  // UI State
  bool _isReady = false;
  List<MediaDeviceInfo> _cameras = [];
  MediaDeviceInfo? _selectedCamera;
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
      await _localRenderer.initialize();
      // En WebRTC, pedimos la lista de dispositivos
      final devices = await navigator.mediaDevices.enumerateDevices();
      _cameras = devices.where((d) => d.kind == 'videoinput').toList();
      
      await _initCamera();
      await _initSignalingServer();
      
      // Obtener IP local para mostrar al usuario
      final ip = await NetworkInfo().getWifiIP();
      setState(() {
        _localIp = ip ?? "127.0.0.1";
      });
      
    } catch (e) {
      debugPrint('Error inicializando: $e');
    }
  }

  String? _errorMessage;

  Future<void> _initCamera([MediaDeviceInfo? camera]) async {
    _selectedCamera = camera ?? (_cameras.isNotEmpty ? _cameras.first : null);
    
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop());
    }

    String minWidth = '1280';
    String minHeight = '720';
    if (_currentResolution == ResolutionPreset.max || _currentResolution == ResolutionPreset.ultraHigh || _currentResolution == ResolutionPreset.veryHigh) {
      minWidth = '1920';
      minHeight = '1080';
    } else if (_currentResolution == ResolutionPreset.high) {
      minWidth = '1280';
      minHeight = '720';
    } else {
      minWidth = '640';
      minHeight = '480';
    }

    final Map<String, dynamic> mediaConstraints = {
      'audio': false,
      'video': {
        'mandatory': {
          'minWidth': minWidth,
          'minHeight': minHeight,
          'minFrameRate': _currentFps.toString(),
        },
        'facingMode': 'environment',
        'optional': _selectedCamera != null ? [{'sourceId': _selectedCamera!.deviceId}] : [],
      }
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      
      if (_isStreaming && _peerConnection != null) {
        final videoTrack = _localStream!.getVideoTracks().first;
        final senders = await _peerConnection!.getSenders();
        for (var sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(videoTrack);
          }
        }
      }

      if (mounted) {
        setState(() {
          _isReady = true;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint("Error iniciando cámara WebRTC: $e");
      if (mounted) {
        setState(() {
          _errorMessage = "Fallo al iniciar cámara: $e";
          _isReady = true; // Desbloquear UI
        });
      }
    }
  }

  Future<void> _initSignalingServer() async {
    _signalingServer = LocalSignalingServer();
    
    _signalingServer!.onClientConnected = (clientId) {
      setState(() => _connectedClientsCount = 1);
      if (_isStreaming) {
        _startWebRTCStream();
      }
    };
    
    _signalingServer!.onClientDisconnected = (clientId) {
      setState(() => _connectedClientsCount = 0);
      _peerConnection?.close();
      _peerConnection = null;
    };
    
    _signalingServer!.onRemoteControlStatusChanged = (connected) {
      setState(() => _isRemoteControlConnected = connected);
    };

    _signalingServer!.onRemoteCommandReceived = (message) async {
      final type = message['type'];
      if (type == 'switch_lens') {
        if (_cameras.isNotEmpty && _selectedCamera != null) {
          int currentIndex = _cameras.indexOf(_selectedCamera!);
          int nextIndex = (currentIndex + 1) % _cameras.length;
          setState(() {
            _selectedCamera = _cameras[nextIndex];
            _isReady = false;
          });
          await _initCamera(_selectedCamera);
        }
      } else if (type == 'set_resolution') {
        final val = message['value'];
        ResolutionPreset preset = ResolutionPreset.veryHigh;
        if (val == 'high') preset = ResolutionPreset.high;
        if (val == 'max') preset = ResolutionPreset.max;
        
        if (preset != _currentResolution) {
          setState(() {
            _currentResolution = preset;
            _isReady = false;
          });
          await _initCamera(_selectedCamera);
        }
      } else if (type == 'set_fps') {
        final fps = (message['value'] is int) ? message['value'] : int.tryParse(message['value'].toString()) ?? 30;
        if (fps != _currentFps) {
          setState(() {
            _currentFps = fps;
            _isReady = false;
          });
          await _initCamera(_selectedCamera);
        }
      }
    };

    _signalingServer!.onMessageReceived = (clientId, message) async {
      final type = message['type'];
      
      if (type == 'answer') {
        final answer = RTCSessionDescription(message['answer']['sdp'], message['answer']['type']);
        await _peerConnection?.setRemoteDescription(answer);
      } else if (type == 'candidate') {
        final candidate = RTCIceCandidate(
          message['candidate']['candidate'],
          message['candidate']['sdpMid'],
          message['candidate']['sdpMLineIndex'],
        );
        await _peerConnection?.addCandidate(candidate);
      }
    };

    await _signalingServer!.start();
  }

  Future<void> _startWebRTCStream() async {
    if (_localStream == null) return;

    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    };

    // Cerrar la conexión anterior si existe
    if (_peerConnection != null) {
      await _peerConnection!.close();
    }

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (candidate) {
      _signalingServer!.sendMessageToAll({
        'type': 'candidate',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        }
      });
    };

    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _signalingServer!.sendMessageToAll({
      'type': 'offer',
      'offer': {
        'type': offer.type,
        'sdp': offer.sdp
      }
    });

    setState(() {
      _isStreaming = true;
    });
  }

  void _stopWebRTCStream() {
    _peerConnection?.close();
    _peerConnection = null;
    setState(() {
      _isStreaming = false;
    });
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _localStream?.getTracks().forEach((track) => track.stop());
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
    // Hemos perdido Zoom y Exposición nativa por el cambio a WebRTC. 
    // Mantenemos solo el selector de lentes y un mensaje de aviso.
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
                  const Text("Ajustes de Lente (WebRTC)", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  Row(
                    children: [
                      const Icon(Icons.camera_alt, color: Colors.white),
                      const SizedBox(width: 10),
                      const Text("Lente:", style: TextStyle(color: Colors.white)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButton<MediaDeviceInfo>(
                          dropdownColor: Colors.black87,
                          isExpanded: true,
                          value: _selectedCamera,
                          style: const TextStyle(color: Colors.white),
                          items: _cameras.map((c) {
                            return DropdownMenuItem(
                              value: c,
                              child: Text(c.label.isNotEmpty ? c.label : "Cámara ${c.deviceId}", overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (newCamera) async {
                            if (newCamera != null && newCamera != _selectedCamera) {
                              Navigator.pop(context);
                              setState(() => _isReady = false);
                              await _initCamera(newCamera);
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
                          value: _currentFps,
                          style: const TextStyle(color: Colors.white),
                          items: [24, 30, 60].map((fps) {
                            return DropdownMenuItem(
                              value: fps,
                              child: Text("$fps FPS"),
                            );
                          }).toList(),
                          onChanged: (newFps) async {
                            if (newFps != null && newFps != _currentFps) {
                              Navigator.pop(context);
                              setState(() {
                                _currentFps = newFps;
                                _isReady = false;
                              });
                              await _initCamera(_selectedCamera);
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
    if (!_isReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_errorMessage != null || _localStream == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 60),
                const SizedBox(height: 20),
                Text(_errorMessage ?? "Error desconocido al acceder a la cámara.", 
                     textAlign: TextAlign.center, 
                     style: const TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    setState(() { _isReady = false; });
                    _initCamera();
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
          // Visor WebRTC sin distorsión (Se adapta a horizontal y vertical)
          Positioned.fill(
            child: RTCVideoView(
              _localRenderer, 
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
                          _buildStatusChip(Icons.tv, _localIp),
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
                            "${_currentResolution.name.toUpperCase()} @ ${_currentFps}fps",
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
                            _stopWebRTCStream();
                          } else {
                            _startWebRTCStream();
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
