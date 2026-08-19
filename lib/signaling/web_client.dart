const String webClientHtml = '''
<!DOCTYPE html>
<html>
<head>
    <title>WorshipCam Studio - OBS Source</title>
    <style>
        body { margin: 0; padding: 0; background-color: black; overflow: hidden; }
        video, #usbImage { width: 100vw; height: 100vh; object-fit: contain; }
    </style>
</head>
<body>
    <div id="debug-overlay" style="position: absolute; top: 10px; left: 10px; color: white; text-shadow: 1px 1px 2px black; font-family: monospace; z-index: 9999;"></div>
    <video id="remoteVideo" autoplay playsinline muted></video>
    <img id="usbImage" style="display: none;" />
    <script>
        const remoteVideo = document.getElementById('remoteVideo');
        const usbImage = document.getElementById('usbImage');
        const debugOverlay = document.getElementById('debug-overlay');
        let prevBlobUrl = null;

        function log(msg) {
            console.log(msg);
            const p = document.createElement('p');
            p.innerText = new Date().toLocaleTimeString() + ': ' + msg;
            debugOverlay.appendChild(p);
            if (debugOverlay.childNodes.length > 15) {
                debugOverlay.removeChild(debugOverlay.firstChild);
            }
        }

        const config = {
            'iceServers': [
                {'urls': 'stun:stun.l.google.com:19302'}
            ]
        };

        function connect() {
            log('Conectando WebSocket...');
            const ws = new WebSocket(`ws://\${window.location.host}/ws`);
            ws.binaryType = 'blob'; // Importante para MJPEG
            
            let peerConnection;
            let hasLoggedRes = false;

            ws.onopen = () => log('WebSocket conectado. Esperando Oferta WebRTC o Frames USB...');
            ws.onclose = () => {
                log('WebSocket desconectado. Reconectando en 2s...');
                setTimeout(connect, 2000);
            };
            ws.onerror = (e) => log('WebSocket Error.');

            ws.onmessage = async (event) => {
                // MODO USB (MJPEG por WebSocket)
                if (event.data instanceof Blob) {
                    remoteVideo.style.display = 'none';
                    usbImage.style.display = 'block';

                    const newUrl = URL.createObjectURL(event.data);
                    usbImage.onload = () => {
                        if (!hasLoggedRes) {
                            log(`Resolución USB: \${usbImage.naturalWidth}x\${usbImage.naturalHeight}`);
                            hasLoggedRes = true;
                        }
                        if (prevBlobUrl) URL.revokeObjectURL(prevBlobUrl);
                        prevBlobUrl = newUrl;
                    };
                    usbImage.src = newUrl;
                    return;
                }

                // MODO WI-FI (Señalización WebRTC)
                try {
                    const message = JSON.parse(event.data);
                    
                    if (message.type === 'offer') {
                        remoteVideo.style.display = 'block';
                        usbImage.style.display = 'none';
                        log('Procesando Oferta SDP (Modo Wi-Fi)...');
                        
                        if (peerConnection) {
                            peerConnection.close();
                        }

                        peerConnection = new RTCPeerConnection(config);
                        peerConnection.ontrack = (event) => {
                            log('Track de video recibido!');
                            if (remoteVideo.srcObject !== event.streams[0]) {
                                remoteVideo.srcObject = event.streams[0];
                                log('Aplicando stream al tag video...');
                            }
                        };

                        peerConnection.onconnectionstatechange = () => {
                            log('WebRTC State: ' + peerConnection.connectionState);
                        };
                        peerConnection.oniceconnectionstatechange = () => {
                            log('ICE State: ' + peerConnection.iceConnectionState);
                        };

                        peerConnection.onicecandidate = (event) => {
                            if (event.candidate) {
                                ws.send(JSON.stringify({
                                    'type': 'candidate',
                                    'candidate': event.candidate
                                }));
                                const candStr = event.candidate.candidate || '';
                                const parts = candStr.split(' ');
                                let ip = 'desconocida';
                                if (parts.length > 4) {
                                    ip = parts[4];
                                }
                                log('ICE cand (PC): ' + ip);
                            } else {
                                log('Fin de generacion de ICE.');
                            }
                        };

                        await peerConnection.setRemoteDescription(new RTCSessionDescription(message.offer));
                        log('SDP Remoto establecido.');
                        const answer = await peerConnection.createAnswer();
                        await peerConnection.setLocalDescription(answer);
                        log('SDP Local establecido. Enviando Respuesta.');

                        ws.send(JSON.stringify({
                            'type': 'answer',
                            'answer': answer
                        }));
                    } else if (message.type === 'candidate') {
                        if (peerConnection) {
                            peerConnection.addIceCandidate(new RTCIceCandidate(message.candidate));
                            const candStr = message.candidate.candidate || '';
                            const parts = candStr.split(' ');
                            if (parts.length > 4) {
                                log('Remoto IP: ' + parts[4]);
                            }
                        }
                    }
                } catch (e) {
                    // Si no es JSON ni Blob, ignorar o loguear
                }
            };
        }

        connect();
    </script>
</body>
</html>
''';
