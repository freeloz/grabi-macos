# Grabi

**Graba tu pantalla sin drama.** Grabi es un grabador de pantalla nativo de
macOS que vive en la barra de menú: abres, presionas el punto rojo, listo.
Lo contrario de OBS.

- **4 fuentes independientes**, cualquier combinación: pantalla (completa,
  una ventana o una región), cámara selfie, micrófono y audio del sistema.
- **Cámara en picture-in-picture** con forma (círculo / cuadrado /
  rectángulo), posición y tamaño libres — modificables **en vivo** durante
  la grabación, arrastrando el recuadro flotante que siempre ves mientras
  grabas. En espejo, como toda selfie.
- **Vista previa en vivo**: lo que ves es exactamente lo que se graba.
- **Pausa/reanuda** sin dejar huecos en el archivo. Pastilla flotante con
  cronómetro, excluida de la grabación (igual que todas las ventanas de Grabi).
- **Un solo .mov** con video HEVC por hardware y el micrófono y el audio del
  sistema en **dos pistas separadas** (~2,2 GB/hora observados a 1080p).
- Selector visual de pantallas y ventanas con miniaturas, borde rojo
  alrededor del área grabada, notificación con miniatura al terminar,
  onboarding con Grabi (la mascota), atajos globales ⌘⇧2 y ⌘⇧P.
- En español, con la voz de la marca. Todo local: nada sale de tu Mac.

## Compilar y ejecutar

Requisitos: macOS 13+, Swift 5.9+ (bastan las Command Line Tools), sin
dependencias externas — solo frameworks de Apple.

```bash
./make-app.sh          # compila (release) y empaqueta dist/Grabi.app
open dist/Grabi.app
```

`make-app.sh` firma con la identidad local **"Grabi Dev"** si existe en tu
llavero (créala una vez: Acceso a Llaveros → Asistente para Certificados →
Crear certificado → tipo *Firma de código*, nombre `Grabi Dev`). Con firma
estable, los permisos de pantalla/cámara/mic sobreviven a las
recompilaciones; con firma ad-hoc, macOS re-pide el permiso de pantalla en
cada build.

Verificación del motor (sin permisos, corre en cualquier máquina):

```bash
swift run EngineChecks
```

Prueba de resistencia (memoria estable en grabaciones largas):

```bash
./scripts/monitor-memoria.sh   # mientras grabas 30-60 min
```

## Arquitectura

Swift Package con tres targets:

```
Sources/
├── RecordEngine/    El motor. Cero UI.
│   ├── RecordEngine.swift       Fachada: preflight → preview → start/pause/stop
│   ├── CapturePipeline.swift    Captura compartida entre vista previa y grabación
│   ├── ScreenCapturer.swift     ScreenCaptureKit: pantalla/ventana/región + audio sistema
│   ├── CameraCapturer.swift     AVFoundation: cámara
│   ├── MicrophoneCapturer.swift AVFoundation: micrófono (canales nativos)
│   ├── PiPCompositor.swift      Core Image + Metal: PiP con formas, en GPU
│   ├── MovieWriter.swift        AVAssetWriter en streaming; pausa por offset de PTS
│   └── Preflight.swift          Disponibilidad y permisos por fuente
├── RecordUI/        El sistema de diseño Grabi (design/) como SwiftUI.
│   ├── Tokens.swift             Colores claro/oscuro, espaciado, radios, movimiento
│   ├── Mascot.swift             La mascota y el semáforo (8 poses)
│   └── …                        Botones, filas de fuente, segmented, toasts, galería
├── RecordApp/       La app de barra de menú (panel, vista previa, overlays…)
└── EngineChecks/    Verificación de integración del motor
```

Decisiones clave del motor:

- **Un pipeline, dos consumidores**: la vista previa y el writer comparten
  capturadores y compositor; empezar a grabar solo "engancha" el writer.
- **Sincronización**: todas las fuentes estampan PTS con el host clock; el
  writer arranca su sesión en el primer frame de video y AVAssetWriter
  alinea el resto. La pausa acumula un offset (medido con el mismo reloj)
  que se resta a cada PTS: N pausas, cero huecos.
- **Thread-safety**: los buffers llegan por colas distintas; todos los
  appends se serializan en la cola interna del writer.
- **Streaming a disco**: nunca se acumulan frames en RAM; los que llegan
  con el encoder ocupado se descartan (tiempo real).

`design/` contiene el manual de marca, el sistema de diseño y el prototipo
aprobado (Fases 0–4): es la especificación de la UI. La galería interna
(Ajustes → Galería del sistema) muestra cada componente en todos sus estados
para verificar fidelidad.

## Ajustes

- **Calidad de grabación** (v0.1.1): *Estándar* (hasta 1080p, ~3 GB/hora,
  por defecto) o *Nítida* (resolución nativa de la fuente hasta 4K; el
  bitrate escala proporcionalmente al área de píxeles para mantener la
  calidad por píxel, con tope de 32 Mbps). El aspecto siempre se conserva.
- **Carpeta de grabaciones** y **atajos globales** (⌘⇧2 · ⌘⇧P).

## Permisos

Grabi necesita Grabación de Pantalla (incluye el audio del sistema), Cámara
y Micrófono — solo para grabar; la app lo explica y te lleva al panel
exacto de Ajustes del Sistema. Si una fuente no está disponible o le falta
permiso, Grabi avisa **antes** de iniciar y ofrece grabar sin ella.

## Limitaciones conocidas (v0.1)

- Distribución: sin cuenta de Apple Developer no hay notarización; la app
  solo corre en máquinas donde se compile/firme localmente.
- La captura de ventana sigue a la ventana, pero el borde indicador y el
  mapeo del recuadro selfie usan la posición que tenía al iniciar.
- Selector de dispositivos (otra cámara/mic) y ajustes de calidad: fuera de
  alcance de v0.1 a propósito.
