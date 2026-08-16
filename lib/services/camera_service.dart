import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum ResolutionPreset { low, medium, high, veryHigh, ultraHigh, max }

class CameraService extends ChangeNotifier {
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  MediaStream? localStream;
  RTCPeerConnection? peerConnection;
  
  List<MediaDeviceInfo> cameras = [];
  MediaDeviceInfo? selectedCamera;
  ResolutionPreset currentResolution = ResolutionPreset.veryHigh;
  int currentFps = 30;

  bool isReady = false;
  String? errorMessage;

  Future<void> initialize() async {
    await localRenderer.initialize();
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      cameras = devices.where((d) => d.kind == 'videoinput').toList();
      await startCamera();
    } catch (e) {
      errorMessage = "Error inicializando dispositivos: $e";
      notifyListeners();
    }
  }

  Future<void> startCamera([MediaDeviceInfo? camera]) async {
    selectedCamera = camera ?? (cameras.isNotEmpty ? cameras.first : null);
    
    if (localStream != null) {
      localStream!.getTracks().forEach((track) => track.stop());
    }

    String minWidth = '1280';
    String minHeight = '720';
    if (currentResolution == ResolutionPreset.max || currentResolution == ResolutionPreset.ultraHigh || currentResolution == ResolutionPreset.veryHigh) {
      minWidth = '1920';
      minHeight = '1080';
    } else if (currentResolution == ResolutionPreset.high) {
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
          'minFrameRate': currentFps.toString(),
        },
        'facingMode': 'environment',
        'optional': selectedCamera != null ? [{'sourceId': selectedCamera!.deviceId}] : [],
      }
    };

    try {
      localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      localRenderer.srcObject = localStream;
      
      // Si estamos en medio de un stream activo, reemplazar el track "en caliente"
      if (peerConnection != null) {
        final videoTrack = localStream!.getVideoTracks().first;
        final senders = await peerConnection!.getSenders();
        for (var sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(videoTrack);
          }
        }
      }

      isReady = true;
      errorMessage = null;
      notifyListeners();
    } catch (e) {
      debugPrint("Error iniciando cámara WebRTC: $e");
      errorMessage = "Fallo al iniciar cámara: $e";
      isReady = true; // Desbloqueamos UI para mostrar error
      notifyListeners();
    }
  }

  void switchLens() async {
    if (cameras.isNotEmpty && selectedCamera != null) {
      int currentIndex = cameras.indexOf(selectedCamera!);
      int nextIndex = (currentIndex + 1) % cameras.length;
      selectedCamera = cameras[nextIndex];
      isReady = false;
      notifyListeners();
      await startCamera(selectedCamera);
    }
  }

  void setResolution(ResolutionPreset preset) async {
    if (preset != currentResolution) {
      currentResolution = preset;
      isReady = false;
      notifyListeners();
      await startCamera(selectedCamera);
    }
  }

  void setFps(int fps) async {
    if (fps != currentFps) {
      currentFps = fps;
      isReady = false;
      notifyListeners();
      await startCamera(selectedCamera);
    }
  }

  bool isFlashOn = false;

  Future<void> toggleFlash() async {
    if (localStream != null) {
      final videoTracks = localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        final track = videoTracks.first;
        final hasTorch = await track.hasTorch();
        if (hasTorch) {
          isFlashOn = !isFlashOn;
          await track.setTorch(isFlashOn);
          notifyListeners();
        } else {
          debugPrint("Este lente no soporta Flash/Torch.");
        }
      }
    }
  }

  @override
  void dispose() {
    localRenderer.dispose();
    localStream?.getTracks().forEach((track) => track.stop());
    peerConnection?.close();
    super.dispose();
  }
}
