const String webClientHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WorshipCam Studio - OBS Source</title>
    <style>
        body { margin: 0; padding: 0; background-color: black; overflow: hidden; }
        video { width: 100vw; height: 100vh; object-fit: contain; }
    </style>
</head>
<body>
    <video id="remoteVideo" autoplay playsinline muted></video>
    <script>
        const video = document.getElementById('remoteVideo');
        const ws = new WebSocket(`ws://\${window.location.host}/ws`);
        let peerConnection;

        const config = {
            // Usamos el servidor STUN gratuito de Google por si están en diferentes subredes,
            // aunque localmente no debería necesitarlo.
            'iceServers': [{ 'urls': 'stun:stun.l.google.com:19302' }]
        };

        ws.onmessage = async (event) => {
            const message = JSON.parse(event.data);

            if (message.type === 'offer') {
                peerConnection = new RTCPeerConnection(config);
                
                // Cuando recibimos el stream de video, lo ponemos en el elemento <video>
                peerConnection.ontrack = (event) => {
                    if (video.srcObject !== event.streams[0]) {
                        video.srcObject = event.streams[0];
                        // Forzamos el play por las políticas de autoplay de OBS/Chrome
                        video.play().catch(e => console.error(e));
                    }
                };

                // Enviamos candidatos ICE de vuelta al celular
                peerConnection.onicecandidate = (event) => {
                    if (event.candidate) {
                        ws.send(JSON.stringify({
                            'type': 'candidate',
                            'candidate': event.candidate
                        }));
                    }
                };

                // Aceptamos la oferta
                await peerConnection.setRemoteDescription(new RTCSessionDescription(message.offer));
                const answer = await peerConnection.createAnswer();
                await peerConnection.setLocalDescription(answer);

                // Enviamos la respuesta
                ws.send(JSON.stringify({
                    'type': 'answer',
                    'answer': answer
                }));
            } else if (message.type === 'candidate') {
                // Recibimos un candidato ICE del celular
                if (peerConnection) {
                    await peerConnection.addIceCandidate(new RTCIceCandidate(message.candidate));
                }
            }
        };

        ws.onopen = () => {
            console.log('Connected to WorshipCam Studio signaling server');
        };
    </script>
</body>
</html>
''';
