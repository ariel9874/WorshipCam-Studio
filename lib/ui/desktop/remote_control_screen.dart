import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../services/adb_service.dart';
import '../../services/discovery_service.dart';
import '../../services/remote_control_client.dart';
import '../../services/serial_service.dart';
import 'camera_node.dart';

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({Key? key}) : super(key: key);

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  final TextEditingController _ipController = TextEditingController(text: '127.0.0.1');
  
  // Multiview State
  final List<CameraNode> _cameras = [];
  CameraNode? _activeCamera;

  bool _isTunnelActive = false;
  bool _isDiscovering = false;

  // Serial / ESP32
  final _serialService = SerialService();
  StreamSubscription<String>? _serialSubscription;
  bool _isSerialConnected = false;
  String? _selectedComPort;

  @override
  void initState() {
    super.initState();
    _setupTunnel();
    
    // Escuchar mensajes provenientes del ESP32 Maestro (Ej: Botón del Joystick)
    _serialSubscription = _serialService.onMessage.listen((msg) {
      if (msg == "JOYSTICK:CLICK") {
        _activeCamera?.client?.sendCommand('toggle_flash', null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚡ Flash / Foco alternado desde el Joystick")),
        );
      }
    });
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
        _addCamera(ip);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontraron celulares en la red.')));
      }
    }
  }

  void _addCamera(String ip) async {
    // Evitar duplicados
    if (_cameras.any((c) => c.ip == ip)) return;

    final node = CameraNode(ip: ip);
    await node.initialize();
    
    node.client = RemoteControlClient(
      onConnected: () {
        if (mounted) setState(() => node.isConnected = true);
      },
      onDisconnected: () {
        if (mounted) setState(() => node.isConnected = false);
      },
      onError: (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error en $ip: $err'), backgroundColor: Colors.red));
        }
      }
    );

    setState(() {
      _cameras.add(node);
      if (_activeCamera == null) _activeCamera = node;
    });

    node.client!.connect(ip);
    _startVideoMonitor(node);
  }

  void _removeCamera(CameraNode node) {
    node.dispose();
    setState(() {
      _cameras.remove(node);
      if (_activeCamera == node) {
        _activeCamera = _cameras.isNotEmpty ? _cameras.first : null;
      }
    });
  }

  Future<void> _startVideoMonitor(CameraNode node) async {
    final url = 'ws://${node.ip}:8080/ws';
    node.webrtcChannel = WebSocketChannel.connect(Uri.parse(url));
    
    final configuration = {'iceServers': []};
    node.peerConnection = await createPeerConnection(configuration);
    
    node.peerConnection!.onIceCandidate = (candidate) {
      node.webrtcChannel!.sink.add(jsonEncode({
        'type': 'candidate',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        }
      }));
    };
    
    node.peerConnection!.onTrack = (event) {
      if (event.track.kind == 'video') {
        node.renderer.srcObject = event.streams[0];
        if (mounted) setState(() {});
      }
    };
    
    node.webrtcChannel!.stream.listen((message) async {
      final data = jsonDecode(message);
      final type = data['type'];
      
      if (type == 'offer') {
        final offer = RTCSessionDescription(data['offer']['sdp'], data['offer']['type']);
        await node.peerConnection!.setRemoteDescription(offer);
        final answer = await node.peerConnection!.createAnswer();
        await node.peerConnection!.setLocalDescription(answer);
        
        node.webrtcChannel!.sink.add(jsonEncode({
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
        await node.peerConnection!.addCandidate(candidate);
      }
    }, onDone: () {
      if (mounted) setState(() => node.isMonitoring = false);
    });
    
    if (mounted) setState(() => node.isMonitoring = true);
  }

  @override
  void dispose() {
    _serialSubscription?.cancel();
    _serialService.disconnect();
    
    for (var node in _cameras) {
      node.dispose();
    }
    _ipController.dispose();
    
    if (_isTunnelActive) {
      AdbService.removeUSBTunnel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveCamera = _activeCamera != null && _activeCamera!.isConnected;
    
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('WorshipCam Studio Multiview', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.2)),
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: _isSerialConnected ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
              border: Border.all(color: _isSerialConnected ? Colors.green : Colors.orangeAccent),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                _isSerialConnected ? "PTZ EN LÍNEA" : "PTZ DESCONECTADO",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _isSerialConnected ? Colors.greenAccent : Colors.orangeAccent),
              ),
            ),
          )
        ],
      ),
      body: Row(
        children: [
          // Área de Video (Grid)
          Expanded(
            flex: 3,
            child: Column(
              children: [
                // Top Bar for Adding Cameras
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF222222),
                  child: Row(
                    children: [
                      const Icon(Icons.videocam, color: Colors.white70),
                      const SizedBox(width: 10),
                      const Text("Cámaras Conectadas", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      SizedBox(
                        width: 200,
                        height: 40,
                        child: TextField(
                          controller: _ipController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Ej. 192.168.1.10',
                            hintStyle: const TextStyle(color: Colors.white38),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            filled: true,
                            fillColor: Colors.black54,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text("Añadir IP"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                        onPressed: () {
                          if (_ipController.text.isNotEmpty) {
                            _addCamera(_ipController.text);
                          }
                        },
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: _isDiscovering ? null : _discoverDevice,
                        icon: _isDiscovering 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.search, color: Colors.blueAccent),
                        tooltip: "Buscar en Wi-Fi",
                      )
                    ],
                  ),
                ),
                
                // Grid View
                Expanded(
                  child: _cameras.isEmpty 
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.grid_view, color: Colors.white24, size: 80),
                            SizedBox(height: 16),
                            Text("No hay cámaras. Añade una IP o busca en la red.", style: TextStyle(color: Colors.white54, fontSize: 16)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _cameras.length <= 2 ? 1 : 2,
                          childAspectRatio: 16 / 9,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _cameras.length,
                        itemBuilder: (context, index) {
                          final node = _cameras[index];
                          final isActive = _activeCamera == node;
                          
                          return GestureDetector(
                            onTap: () => setState(() => _activeCamera = node),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isActive ? Colors.orangeAccent : const Color(0xFF333333), 
                                  width: isActive ? 3 : 2
                                ),
                                boxShadow: isActive ? [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 10)] : null,
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: node.isMonitoring
                                        ? RTCVideoView(node.renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)
                                        : const Center(child: Icon(Icons.videocam_off, color: Colors.white24, size: 50)),
                                  ),
                                  // Overlay
                                  Positioned(
                                    top: 8, left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                                      child: Row(
                                        children: [
                                          Icon(Icons.circle, size: 10, color: node.isConnected ? Colors.greenAccent : Colors.redAccent),
                                          const SizedBox(width: 6),
                                          Text("CAM ${index + 1} (${node.ip})", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 8, right: 8,
                                    child: IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white70),
                                      onPressed: () => _removeCamera(node),
                                    ),
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                ),
              ],
            ),
          ),

          // Panel de Control (Afecta a _activeCamera)
          Container(
            width: 380,
            decoration: const BoxDecoration(
              color: Color(0xFF222222),
              border: Border(left: BorderSide(color: Color(0xFF333333))),
            ),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _activeCamera != null ? Colors.orange.withOpacity(0.1) : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _activeCamera != null ? Colors.orangeAccent.withOpacity(0.5) : Colors.transparent),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.tune, color: Colors.white70),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _activeCamera != null ? "Controlando: ${_activeCamera!.ip}" : "Ninguna cámara seleccionada",
                          style: TextStyle(color: _activeCamera != null ? Colors.orangeAccent : Colors.white54, fontWeight: FontWeight.bold),
                        ),
                      )
                    ],
                  ),
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
                        _buildPtzButton(icon: Icons.keyboard_arrow_up, command: "TILT", action: "UP"),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildPtzButton(icon: Icons.keyboard_arrow_left, command: "PAN", action: "LEFT"),
                            const SizedBox(width: 20),
                            IconButton(
                              icon: const Icon(Icons.center_focus_strong, size: 30, color: Colors.orangeAccent),
                              onPressed: () => _serialService.sendCommand("PTZ:CENTER"),
                              tooltip: "Ir al Centro (Homing)",
                            ),
                            const SizedBox(width: 20),
                            _buildPtzButton(icon: Icons.keyboard_arrow_right, command: "PAN", action: "RIGHT"),
                          ],
                        ),
                        _buildPtzButton(icon: Icons.keyboard_arrow_down, command: "TILT", action: "DOWN"),
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
                  onTap: () => _activeCamera?.client?.sendCommand('switch_lens', null),
                  enabled: hasActiveCamera,
                ),
                
                _buildControlCard(
                  title: "Activar/Desactivar Flash",
                  icon: Icons.flash_on,
                  onTap: () => _activeCamera?.client?.sendCommand('toggle_flash', null),
                  enabled: hasActiveCamera,
                ),

                const SizedBox(height: 20),
                const Text("CALIDAD", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                _buildSegmentedControl(
                  title: "Resolución",
                  items: const ['max', 'high', 'medium'],
                  labels: const ['4K/Max', '1080p', '720p'],
                  selectedValue: _selectedRes,
                  enabled: hasActiveCamera,
                  onChanged: (val) {
                    setState(() => _selectedRes = val);
                    _activeCamera?.client?.sendCommand('set_resolution', val);
                  },
                ),
                
                const SizedBox(height: 20),
                
                _buildSegmentedControl(
                  title: "Velocidad (FPS)",
                  items: const ['24', '30', '60'],
                  labels: const ['24fps', '30fps', '60fps'],
                  selectedValue: _selectedFps,
                  enabled: hasActiveCamera,
                  onChanged: (val) {
                    setState(() => _selectedFps = val);
                    _activeCamera?.client?.sendCommand('set_fps', int.parse(val));
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

  Widget _buildControlCard({required String title, required IconData icon, required VoidCallback onTap, required bool enabled}) {
    return InkWell(
      onTap: enabled ? onTap : null,
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
            Icon(icon, color: enabled ? Colors.white : Colors.white38, size: 20),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: TextStyle(color: enabled ? Colors.white : Colors.white38, fontSize: 14, fontWeight: FontWeight.w500))),
            Icon(Icons.chevron_right, color: enabled ? Colors.white54 : Colors.white24, size: 20),
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
    required bool enabled,
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
                  onTap: enabled ? () => onChanged(items[index]) : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected && enabled ? Colors.blueAccent : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Center(
                      child: Text(
                        labels[index], 
                        style: TextStyle(
                          color: enabled ? (isSelected ? Colors.white : Colors.white54) : Colors.white24,
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
