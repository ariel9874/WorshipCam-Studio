import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../services/adb_service.dart';
import '../../services/discovery_service.dart';
import '../../services/remote_control_client.dart';
import '../../services/serial_service.dart';

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({Key? key}) : super(key: key);

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final TextEditingController _ipController = TextEditingController(text: '127.0.0.1');
  RemoteControlClient? _client;
  bool _isConnected = false;
  bool _isTunnelActive = false;
  bool _isDiscovering = false;

  // Serial / ESP32
  final _serialService = SerialService();
  bool _isSerialConnected = false;
  String? _selectedComPort;

  // WebRTC Monitor
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  WebSocketChannel? _webrtcChannel;
  bool _isMonitoring = false;

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();
    _client = RemoteControlClient(
      onConnected: () => setState(() => _isConnected = true),
      onDisconnected: () => setState(() => _isConnected = false),
      onError: (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red));
        }
      }
    );
    _setupTunnel();
  }

  Future<void> _setupTunnel() async {
    final success = await AdbService.setupUSBTunnel();
    if (mounted) {
      setState(() => _isTunnelActive = success);
    }
  }

  Future<void> _discoverDevice() async {
    setState(() => _isDiscovering = true);
    final ip = await DiscoveryService.discoverDevice();
    
    if (mounted) {
      setState(() => _isDiscovering = false);
      if (ip != null) {
        _ipController.text = ip;
        _connect();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontraron celulares en la red.')));
      }
    }
  }

  void _connect() {
    if (_ipController.text.isNotEmpty) {
      _client?.connect(_ipController.text);
      if (!_isMonitoring) {
        _startVideoMonitor();
      }
    }
  }

  void _disconnect() {
    _client?.disconnect();
    _stopVideoMonitor();
  }

  Future<void> _startVideoMonitor() async {
    final url = 'ws://${_ipController.text}:8080/ws';
    _webrtcChannel = WebSocketChannel.connect(Uri.parse(url));
    
    final configuration = {'iceServers': []};
    
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
    _client?.disconnect();
    _webrtcChannel?.sink.close();
    _peerConnection?.close();
    _remoteRenderer.dispose();
    _ipController.dispose();
    
    if (_isTunnelActive) {
      AdbService.removeUSBTunnel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A), // Dark modern theme
      appBar: AppBar(
        title: const Text('WorshipCam Studio', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.2)),
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
              border: Border.all(color: _isConnected ? Colors.green : Colors.redAccent),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                _isConnected ? "CONECTADO" : "DESCONECTADO",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _isConnected ? Colors.greenAccent : Colors.redAccent),
              ),
            ),
          )
        ],
      ),
      body: Row(
        children: [
          // Área de Video
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF333333), width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 10))
                ]
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_isMonitoring)
                      RTCVideoView(
                        _remoteRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      )
                    else
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam_off_outlined, color: Colors.white24, size: 80),
                            SizedBox(height: 16),
                            Text("Esperando conexión de cámara...", style: TextStyle(color: Colors.white54, fontSize: 16)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Panel de Control
          Container(
            width: 380,
            decoration: const BoxDecoration(
              color: Color(0xFF222222),
              border: Border(left: BorderSide(color: Color(0xFF333333))),
            ),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text("CONEXIÓN CÁMARA", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ipController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'IP del Celular',
                            labelStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.black54,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: _isDiscovering ? null : _discoverDevice,
                        icon: _isDiscovering 
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.search, color: Colors.blueAccent),
                        tooltip: "Buscar en Wi-Fi",
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConnected ? Colors.redAccent : Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: _isConnected ? _disconnect : _connect,
                    child: Text(_isConnected ? "DESCONECTAR" : "CONECTAR", style: const TextStyle(color: Colors.white)),
                  ),
                  
                  const SizedBox(height: 30),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 20),

                  const Text("HARDWARE PTZ (ESP32 MAESTRO)", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          dropdownColor: Colors.black87,
                          isExpanded: true,
                          style: const TextStyle(color: Colors.white),
                          hint: const Text("Puerto COM", style: TextStyle(color: Colors.white54)),
                          value: _selectedComPort,
                          items: _serialService.getAvailablePorts().map((port) {
                            return DropdownMenuItem(value: port, child: Text(port));
                          }).toList(),
                          onChanged: _isSerialConnected ? null : (val) => setState(() => _selectedComPort = val),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh, color: Colors.white54),
                        tooltip: "Escanear puertos",
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isSerialConnected ? Colors.redAccent : Colors.orangeAccent,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () {
                      if (_isSerialConnected) {
                        _serialService.disconnect();
                        setState(() => _isSerialConnected = false);
                      } else if (_selectedComPort != null) {
                        final success = _serialService.connect(_selectedComPort!);
                        setState(() => _isSerialConnected = success);
                      }
                    },
                    child: Text(_isSerialConnected ? "DESCONECTAR ESP32" : "CONECTAR ESP32", style: const TextStyle(color: Colors.white)),
                  ),

                  if (_isSerialConnected) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: Column(
                        children: [
                          _buildPtzButton(
                            icon: Icons.keyboard_arrow_up,
                            command: "TILT",
                            action: "UP",
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildPtzButton(
                                icon: Icons.keyboard_arrow_left,
                                command: "PAN",
                                action: "LEFT",
                              ),
                              const SizedBox(width: 20),
                              IconButton(
                                icon: const Icon(Icons.center_focus_strong, size: 30, color: Colors.orangeAccent),
                                onPressed: () => _serialService.sendCommand("PTZ:CENTER"),
                                tooltip: "Ir al Centro (Homing)",
                              ),
                              const SizedBox(width: 20),
                              _buildPtzButton(
                                icon: Icons.keyboard_arrow_right,
                                command: "PAN",
                                action: "RIGHT",
                              ),
                            ],
                          ),
                          _buildPtzButton(
                            icon: Icons.keyboard_arrow_down,
                            command: "TILT",
                            action: "DOWN",
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 30),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 20),

                  const Text("CÁMARA", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  
                  _buildControlCard(
                    title: "Cambiar Lente",
                    icon: Icons.cameraswitch,
                    onTap: () => _client?.sendCommand('switch_lens', null),
                  ),
                  
                  _buildControlCard(
                    title: "Activar/Desactivar Flash",
                    icon: Icons.flash_on,
                    onTap: () => _client?.sendCommand('toggle_flash', null),
                  ),

                  const SizedBox(height: 20),
                  const Text("CALIDAD", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),

                  _buildSegmentedControl(
                    title: "Resolución",
                    items: const ['max', 'high', 'medium'],
                    labels: const ['4K/Max', '1080p', '720p'],
                    selectedValue: _selectedRes,
                    onChanged: (val) {
                      setState(() => _selectedRes = val);
                      _client?.sendCommand('set_resolution', val);
                    },
                  ),
                  
                  const SizedBox(height: 20),
                  
                  _buildSegmentedControl(
                    title: "Velocidad (FPS)",
                    items: const ['24', '30', '60'],
                    labels: const ['24fps', '30fps', '60fps'],
                    selectedValue: _selectedFps,
                    onChanged: (val) {
                      setState(() => _selectedFps = val);
                      _client?.sendCommand('set_fps', int.parse(val));
                    },
                  ),
                  
                ],
              ),
            )
          ],
        ),
    );
  }

  String _selectedRes = 'max';
  String _selectedFps = '30';

  Widget _buildPtzButton({required IconData icon, required String command, required String action}) {
    return GestureDetector(
      onTapDown: (_) => _serialService.sendCommand("$command:$action"),
      onTapUp: (_) => _serialService.sendCommand("$command:STOP"),
      onTapCancel: () => _serialService.sendCommand("$command:STOP"),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 36, color: Colors.white),
      ),
    );
  }

  Widget _buildControlCard({required String title, required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: _isConnected ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        child: Row(
          children: [
            Icon(icon, color: _isConnected ? Colors.white : Colors.white38, size: 20),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: TextStyle(color: _isConnected ? Colors.white : Colors.white38, fontSize: 14, fontWeight: FontWeight.w500))),
            Icon(Icons.chevron_right, color: _isConnected ? Colors.white54 : Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentedControl({
    required String title, 
    required List<String> items, 
    required List<String> labels, 
    required String selectedValue,
    required Function(String) onChanged
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 8),
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          child: Row(
            children: List.generate(items.length, (index) {
              final isSelected = items[index] == selectedValue;
              return Expanded(
                child: GestureDetector(
                  onTap: _isConnected ? () => onChanged(items[index]) : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blueAccent : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Center(
                      child: Text(
                        labels[index], 
                        style: TextStyle(
                          color: _isConnected ? (isSelected ? Colors.white : Colors.white54) : Colors.white24,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13
                        )
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        )
      ],
    );
  }
}
