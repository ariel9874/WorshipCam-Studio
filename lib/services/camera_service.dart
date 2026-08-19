import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:camera/camera.dart' as cam;

enum ResolutionPreset { low, medium, high, veryHigh, ultraHigh, max }

class CameraService extends ChangeNotifier {
  // --- Canal nativo para conversión YUV→JPEG acelerada por hardware ---
  static const _yuvChannel = MethodChannel('com.example.camo_clone/yuv_converter');

  // --- MODO WI-FI (WebRTC) ---
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  MediaStream? localStream;
  RTCPeerConnection? peerConnection;
  
  List<MediaDeviceInfo> cameras = [];
  MediaDeviceInfo? selectedCamera;

  // --- MODO USB (WebSocket MJPEG) ---
  cam.CameraController? usbCameraController;
  List<cam.CameraDescription> usbCameras = [];
  Function(Uint8List)? onUsbFrame;
  bool isUsbMode = false;
  bool _isProcessingUsbFrame = false;

  // --- COMPARTIDO ---
  ResolutionPreset currentResolution = ResolutionPreset.veryHigh;
  int currentFps = 30;
  bool isReady = false;
  String? errorMessage;
  bool isFlashOn = false;

  Future<void> initialize() async {
    await localRenderer.initialize();
    await loadCameras();
  }

  Future<void> loadCameras() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      cameras = devices.where((d) => d.kind == 'videoinput').toList();
      if (cameras.isNotEmpty && selectedCamera == null) {
        selectedCamera = cameras.first;
      }
      usbCameras = await cam.availableCameras();
      
      if (!isUsbMode) {
        await startCamera();
      } else {
        await startUsbCamera();
      }
    } catch (e) {
      errorMessage = "Error inicializando dispositivos: $e";
      notifyListeners();
    }
  }

  // Activa y cambia el modo de transmisión
  Future<void> setTransmissionMode(bool useUsb) async {
    if (isUsbMode == useUsb) return;
    
    isReady = false;
    errorMessage = null;
    notifyListeners();

    isUsbMode = useUsb;

    if (isUsbMode) {
      // Apagar WebRTC y prender USB
      _stopWebrtc();
      await startUsbCamera();
    } else {
      // Apagar USB y prender WebRTC
      _stopUsb();
      await startCamera();
    }
  }

  void _stopWebrtc() {
    localStream?.getTracks().forEach((track) => track.stop());
    localStream = null;
    peerConnection?.close();
    peerConnection = null;
  }

  void _stopUsb() {
    if (usbCameraController?.value.isStreamingImages == true) {
      usbCameraController?.stopImageStream();
    }
    usbCameraController?.dispose();
    usbCameraController = null;
  }

  // --- LOGICA MODO USB (WebSocket MJPEG) ---
  Future<void> startUsbCamera([cam.CameraDescription? cameraDesc]) async {
    final targetCamera = cameraDesc ?? (usbCameras.isNotEmpty ? usbCameras.first : null);
    if (targetCamera == null) return;

    _stopUsb();

    cam.ResolutionPreset preset = cam.ResolutionPreset.veryHigh;
    if (currentResolution == ResolutionPreset.max) preset = cam.ResolutionPreset.max;
    if (currentResolution == ResolutionPreset.ultraHigh) preset = cam.ResolutionPreset.ultraHigh;
    if (currentResolution == ResolutionPreset.high) preset = cam.ResolutionPreset.high;
    if (currentResolution == ResolutionPreset.medium) preset = cam.ResolutionPreset.medium;
    if (currentResolution == ResolutionPreset.low) preset = cam.ResolutionPreset.low;

    usbCameraController = cam.CameraController(
      targetCamera,
      preset,
      enableAudio: false,
      imageFormatGroup: cam.ImageFormatGroup.yuv420,
    );

    try {
      await usbCameraController!.initialize();
      errorMessage = null;

      usbCameraController!.startImageStream((cam.CameraImage image) async {
        if (_isProcessingUsbFrame) return;
        _isProcessingUsbFrame = true;

        try {
          if (image.format.group == cam.ImageFormatGroup.jpeg) {
            if (image.planes.isNotEmpty) {
              onUsbFrame?.call(image.planes[0].bytes);
            }
          } else {
            // Conversión nativa acelerada por hardware (Android YuvImage)
            final jpegBytes = await _nativeYuv420ToJpeg(image);
            if (jpegBytes != null) {
              onUsbFrame?.call(jpegBytes);
            }
          }
        } catch (e) {
          debugPrint("Error procesando frame USB: $e");
        } finally {
          _isProcessingUsbFrame = false;
        }
      });
      isReady = true;
      notifyListeners();
    } catch (e) {
      errorMessage = "Fallo al iniciar cámara USB: $e";
      isReady = true;
      notifyListeners();
    }
  }

  /// Conversión nativa YUV420 → JPEG usando Android YuvImage (acelerada por hardware)
  Future<Uint8List?> _nativeYuv420ToJpeg(cam.CameraImage image) async {
    try {
      // Calcular rotación necesaria basada en la orientación del sensor
      int rotation = 0;
      if (usbCameraController != null) {
        rotation = usbCameraController!.description.sensorOrientation;
      }

      final result = await _yuvChannel.invokeMethod<Uint8List>('convertYuv420ToJpeg', {
        'y': image.planes[0].bytes,
        'u': image.planes[1].bytes,
        'v': image.planes[2].bytes,
        'width': image.width,
        'height': image.height,
        'yRowStride': image.planes[0].bytesPerRow,
        'uvRowStride': image.planes[1].bytesPerRow,
        'uvPixelStride': image.planes[1].bytesPerPixel ?? 1,
        'quality': 95,
        'rotation': rotation,
      });
      return result;
    } catch (e) {
      debugPrint("Error en conversión nativa YUV→JPEG: $e");
      return null;
    }
  }

  // --- LOGICA MODO WI-FI (WebRTC) ---
  Future<void> startCamera([MediaDeviceInfo? camera]) async {
    selectedCamera = camera ?? (cameras.isNotEmpty ? cameras.first : null);
    
    _stopWebrtc();

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
      isReady = true;
      notifyListeners();
    }
  }

  void switchLens() async {
    if (isUsbMode) {
      if (usbCameras.isNotEmpty && usbCameraController != null) {
        int currentIndex = usbCameras.indexOf(usbCameraController!.description);
        int nextIndex = (currentIndex + 1) % usbCameras.length;
        isReady = false;
        notifyListeners();
        await startUsbCamera(usbCameras[nextIndex]);
      }
    } else {
      if (cameras.isNotEmpty && selectedCamera != null) {
        int currentIndex = cameras.indexOf(selectedCamera!);
        int nextIndex = (currentIndex + 1) % cameras.length;
        selectedCamera = cameras[nextIndex];
        isReady = false;
        notifyListeners();
        await startCamera(selectedCamera);
      }
    }
  }

  void setResolution(ResolutionPreset preset) async {
    if (preset != currentResolution) {
      currentResolution = preset;
      isReady = false;
      notifyListeners();
      if (isUsbMode) {
        await startUsbCamera();
      } else {
        await startCamera(selectedCamera);
      }
    }
  }

  void setFps(int fps) async {
    if (fps != currentFps) {
      currentFps = fps;
      isReady = false;
      notifyListeners();
      if (!isUsbMode) {
        await startCamera(selectedCamera);
      }
      // FPS en USB MJPEG se controla más difícilmente, por ahora re-iniciamos
    }
  }

  Future<void> toggleFlash() async {
    isFlashOn = !isFlashOn;
    if (isUsbMode && usbCameraController != null) {
      await usbCameraController!.setFlashMode(isFlashOn ? cam.FlashMode.torch : cam.FlashMode.off);
      notifyListeners();
    } else if (!isUsbMode && localStream != null) {
      final videoTracks = localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        final track = videoTracks.first;
        final hasTorch = await track.hasTorch();
        if (hasTorch) {
          await track.setTorch(isFlashOn);
          notifyListeners();
        }
      }
    }
  }

  @override
  void dispose() {
    localRenderer.dispose();
    _stopWebrtc();
    _stopUsb();
    super.dispose();
  }
}
