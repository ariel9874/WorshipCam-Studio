import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({Key? key}) : super(key: key);

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final TextEditingController _ipController = TextEditingController(text: '127.0.0.1');
  WebSocketChannel? _channel; // Canal para JSON commands
  bool _isConnected = false;
  bool _isTunnelActive = false;

  // WebRTC Monitor
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  WebSocketChannel? _webrtcChannel; // Canal para Signaling de WebRTC
  bool _isMonitoring = false;

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
    _setupUSBTunnel();
  }

  Future<void> _setupUSBTunnel() async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        debugPrint("Iniciando túnel USB ADB...");
        
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
        
        final result = await Process.run(adbCommand, ['forward', 'tcp:8080', 'tcp:8080']);
        if (result.exitCode == 0) {
          debugPrint("Túnel USB establecido.");
          setState(() {
            _isTunnelActive = true;
          });
        } else {
          debugPrint("Fallo al establecer túnel ADB: ${result.stderr}");
        }
      }
    } catch (e) {
      debugPrint("Error ejecutando adb: $e");
    }
  }

  void _connect() {
    if (_ipController.text.isEmpty) return;

    final url = 'ws://${_ipController.text}:8080/control';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      
      // Enviar un mensaje de ping o identificación inicial
      _sendCommand('ping', 'windows_client');
      
      setState(() {
        _isConnected = true;
      });

      _channel!.stream.listen(
        (message) {
          debugPrint('Mensaje recibido del celular: $message');
        },
        onDone: () {
          setState(() {
            _isConnected = false;
          });
        },
        onError: (error) {
          debugPrint('Error en WebSocket: $error');
          setState(() {
            _isConnected = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de conexión: $error'), backgroundColor: Colors.red));
          }
        },
      );
    } catch (e) {
      debugPrint('Error de conexión: $e');
      setState(() {
        _isConnected = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo conectar: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _disconnect() {
    _channel?.sink.close();
    setState(() {
      _isConnected = false;
    });
  }

  void _sendCommand(String type, dynamic value) {
    if (_channel != null && _isConnected) {
      final msg = jsonEncode({'type': type, 'value': value});
      _channel!.sink.add(msg);
      debugPrint('Enviando comando: $msg');
    }
  }

  Future<void> _startVideoMonitor() async {
    final url = 'ws://${_ipController.text}:8080/ws';
    _webrtcChannel = WebSocketChannel.connect(Uri.parse(url));
    
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    };
    
    _peerConnection = await createPeerConnection(configuration);
    
    _peerConnection!.onIceCandidate = (candidate) {
      _webrtcChannel!.sink.add(jsonEncode({
        'type': 'candidate',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        }
      }));
    };
    
    _peerConnection!.onTrack = (event) {
      if (event.track.kind == 'video') {
        _remoteRenderer.srcObject = event.streams[0];
        setState(() {});
      }
    };
    
    _webrtcChannel!.stream.listen((message) async {
      final data = jsonDecode(message);
      final type = data['type'];
      
      if (type == 'offer') {
        final offer = RTCSessionDescription(data['offer']['sdp'], data['offer']['type']);
        await _peerConnection!.setRemoteDescription(offer);
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        
        _webrtcChannel!.sink.add(jsonEncode({
          'type': 'answer',
          'answer': {
            'type': answer.type,
            'sdp': answer.sdp
          }
        }));
      } else if (type == 'candidate') {
        final candidate = RTCIceCandidate(
          data['candidate']['candidate'],
          data['candidate']['sdpMid'],
          data['candidate']['sdpMLineIndex'],
        );
        await _peerConnection!.addCandidate(candidate);
      }
    }, onDone: () {
      _stopVideoMonitor();
    });
    
    setState(() {
      _isMonitoring = true;
    });
  }

  void _stopVideoMonitor() {
    _webrtcChannel?.sink.close();
    _peerConnection?.close();
    _remoteRenderer.srcObject = null;
    setState(() {
      _isMonitoring = false;
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _webrtcChannel?.sink.close();
    _peerConnection?.close();
    _remoteRenderer.dispose();
    _ipController.dispose();
    
    // Clean up ADB tunnel
    if (_isTunnelActive && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
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
      Process.run(adbCommand, ['forward', '--remove', 'tcp:8080']);
    }
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E), // Dark theme
      appBar: AppBar(
        title: const Text('WorshipCam Remote Panel'),
        backgroundColor: const Color(0xFF282A36),
        actions: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                _isConnected ? "CONECTADO" : "DESCONECTADO",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          )
        ],
      ),
      body: Row(
        children: [
          // Área de Video
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black,
              child: _isMonitoring 
                  ? RTCVideoView(
                      _remoteRenderer, 
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off, color: Colors.white24, size: 80),
                          const SizedBox(height: 10),
                          const Text("Monitor de Video Apagado", style: TextStyle(color: Colors.white54)),
                          const SizedBox(height: 20),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              "ADVERTENCIA: Activar el monitor en PC desconectará a OBS debido a límites de hardware del celular. Úsalo solo para calibración.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _isConnected ? _startVideoMonitor : null,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Iniciar Monitor (Desconecta OBS)'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          )
                        ],
                      ),
                    ),
            ),
          ),
          // Área de Controles
          Container(
            width: 400,
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF1E1E2E),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // Connection Section
              Card(
                color: const Color(0xFF282A36),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text("Conexión a Celular", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      if (_isTunnelActive)
                        Container(
                          margin: const EdgeInsets.only(top: 10, bottom: 10),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                          child: const Row(
                            children: [
                              Icon(Icons.usb, color: Colors.greenAccent),
                              SizedBox(width: 10),
                              Expanded(child: Text("Túnel USB activo. Conexión garantizada por cable.", style: TextStyle(color: Colors.greenAccent, fontSize: 12))),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _ipController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'IP del celular (ej. 192.168.1.15)',
                          labelStyle: TextStyle(color: Colors.grey),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _isConnected ? _disconnect : _connect,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isConnected ? Colors.redAccent : Colors.blueAccent,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: Text(_isConnected ? 'Desconectar' : 'Conectar'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Control Section (Only enabled if connected)
              Opacity(
                opacity: _isConnected ? 1.0 : 0.5,
                child: Card(
                  color: const Color(0xFF282A36),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text("Panel de Control Remoto", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        
                        // Switch Lens Button
                        ElevatedButton.icon(
                          onPressed: _isConnected ? () => _sendCommand('switch_lens', 'next') : null,
                          icon: const Icon(Icons.cameraswitch),
                          label: const Text('Cambiar Lente Físico'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purpleAccent,
                            minimumSize: const Size.fromHeight(50),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Resolution Selector
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Calidad WebRTC:", style: TextStyle(color: Colors.white)),
                            DropdownButton<String>(
                              dropdownColor: Colors.black87,
                              value: 'veryHigh', // Por defecto
                              style: const TextStyle(color: Colors.white),
                              items: const [
                                DropdownMenuItem(value: 'high', child: Text('720p (High)')),
                                DropdownMenuItem(value: 'veryHigh', child: Text('1080p (VeryHigh)')),
                                DropdownMenuItem(value: 'max', child: Text('Máxima')),
                              ],
                              onChanged: _isConnected ? (val) {
                                _sendCommand('set_resolution', val);
                              } : null,
                            ),
                          ],
                        ),

                        // FPS Selector
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Velocidad (FPS):", style: TextStyle(color: Colors.white)),
                            DropdownButton<int>(
                              dropdownColor: Colors.black87,
                              value: 30, // Por defecto
                              style: const TextStyle(color: Colors.white),
                              items: const [
                                DropdownMenuItem(value: 30, child: Text('30 FPS')),
                                DropdownMenuItem(value: 60, child: Text('60 FPS')),
                              ],
                              onChanged: _isConnected ? (val) {
                                _sendCommand('set_fps', val);
                              } : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isMonitoring) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _stopVideoMonitor,
                  icon: const Icon(Icons.stop),
                  label: const Text('Detener Monitor'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                )
              ]
            ],
          ),
        ),
      ),
        ],
      ),
    );
  }
}
