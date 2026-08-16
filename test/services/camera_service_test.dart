import 'package:flutter_test/flutter_test.dart';
import 'package:camo_clone/services/camera_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CameraService inicia con valores por defecto', () {
    final service = CameraService();

    expect(service.isReady, false);
    expect(service.isFlashOn, false);
    expect(service.currentFps, 30);
    expect(service.currentResolution, ResolutionPreset.veryHigh);
    expect(service.cameras, isEmpty);
    expect(service.errorMessage, isNull);
  });

  test('Cambiar FPS actualiza el estado y marca isReady en falso', () {
    final service = CameraService();
    
    // Cambiar fps a 60
    service.setFps(60);

    expect(service.currentFps, 60);
    expect(service.isReady, false);
    // Nota: navigator.mediaDevices lanzará excepción en unit test puro si llega a ejecutarse,
    // pero podemos validar que el estado sincrónico cambió correctamente.
  });

  test('Cambiar resolución actualiza el estado', () {
    final service = CameraService();
    
    service.setResolution(ResolutionPreset.max);

    expect(service.currentResolution, ResolutionPreset.max);
    expect(service.isReady, false);
  });
}
