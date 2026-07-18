# RuedaTec - App de Control de Movilidad

App iOS para controlar sillas de ruedas RuedaTec vía Bluetooth Low Energy (BLE).

## Novedades v2.0

### 🎙️ Control por voz
Di **«adelante»**, **«atrás»**, **«izquierda»**, **«derecha»**, **«velocidad 5»**, **«freno»**… y la silla obedece. Diseñado con seguridad primero:

- **«Alto» / «Para» / «Stop»** se ejecuta al instante y tiene prioridad absoluta.
- Los comandos de movimiento son **impulsos**: la silla se mueve unos segundos (configurable, 1–5 s) y se detiene sola. El modo continuo existe pero está desactivado por defecto.
- Reconocimiento en español (es-MX) con sinónimos en inglés y sesgo hacia el vocabulario de la silla (`contextualStrings`) para mayor precisión.
- Pipeline autorreparable: si el micrófono deja de entregar audio (p. ej. tras reproducir una confirmación o al conectar audífonos), la sesión se rearma sola en ~2 s.
- Confirmaciones habladas (desactivables) con filtro anti-eco por contenido.
- Diagonales por voz: di «adelante» y luego «izquierda» mientras la silla avanza.

### 🛡️ Seguridad
- **Paro de emergencia** siempre visible: detiene la silla y activa el freno en un toque.
- **Sacudir el teléfono** dispara el paro de emergencia (desactivable).
- **Watchdog de movimiento** (firmware v2): la app envía un "latido" cada 300 ms mientras hay movimiento; si el firmware deja de recibirlo (app caída, enlace roto), los motores se detienen solos en ~1.2 s y no aceptan movimiento hasta un paro explícito.
- La silla **se detiene al pasar la app a segundo plano** o al bloquear el teléfono. Si una llamada interrumpe el micrófono, el movimiento por voz se detiene.
- Con el **freno activo se bloquean los comandos de movimiento** (app y firmware), evitando arranques sorpresa al soltar el freno. El freno **se conserva** si se pierde la conexión (silla frenada en rampa = sigue frenada) y su estado real se sincroniza al reconectar.
- El toque siempre manda: si tienes la mano en el pad, la voz no puede interferir, y viceversa cada quien respeta al otro.
- La velocidad inicial se aplica automáticamente al conectar. La velocidad mínima conducible es 1 (el 0 dejaría la silla "aceptando" comandos sin moverse).

### 👁️ Control por la mirada (Eye Control)
- Nuevo modo **«Ojos»** que aprovecha el **Seguimiento ocular integrado de iOS** (Ajustes › Accesibilidad › Seguimiento ocular, iPhone con Face ID + iOS 18). No requiere cámara ni permisos extra: iOS calibra la mirada y mueve el puntero; la app aporta objetivos grandes y bien separados.
- Retícula 3×3 espacial: **mira hacia donde quieres ir** (8 direcciones) y el centro es **ALTO**. La mirada en reposo (al centro) mantiene la silla quieta.
- Mismo modelo de seguridad que la voz: cada permanencia de la mirada = un **impulso** que se detiene solo. Botones grandes de velocidad, freno y paro de emergencia.
- Al ser objetivos grandes, también sirve para **Switch Control** o dedos con poca precisión.

### 🕹️ Controles
- **Modo Joystick (predeterminado)** además del pad direccional: arrastra la perilla, suéltala y se detiene.
- **Velocidad proporcional** opcional: alejar la perilla del centro acelera (niveles 1–9).
- **Orientación horizontal**: en landscape el joystick queda bajo el pulgar derecho y el estado/velocidad/freno en columna a la izquierda.
- Pantalla siempre encendida mientras controlas (opcional).

### 📡 Conexión
- **Reconexión rápida**: la app recuerda tu silla y la reconecta en un toque, sin escanear.
- **Reconexión automática** ante cortes inesperados (hasta 3 intentos).
- **Intensidad de señal en vivo** (barras RSSI) y cronómetro de conexión.
- Los dispositivos RuedaTec se destacan y ordenan primero en el escaneo.
- Telemetría opcional: nivel de batería (`BAT:n`) y versión de firmware (`RT:2.0`).

### 🧰 Otros
- **Ajustes** completos (modo de control, voz, conexión, vibraciones…).
- **Consola de diagnóstico**: comandos enviados, mensajes recibidos y eventos con marca de tiempo.
- Estados claros cuando Bluetooth está apagado o sin permiso.
- Accesibilidad: etiquetas VoiceOver y ajuste de velocidad con gestos de accesibilidad.

## Requisitos

- **iOS**: iPhone con iOS 16.0 o superior
- **Xcode**: 15.0 o superior
- **ESP32**: Con firmware BLE v2 (ver carpeta `esp32_ble/`)

## Configuración del Proyecto

El proyecto usa [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd ruedatecApp
xcodegen generate
open RuedaTec.xcodeproj
```

Luego en **Target → Signing & Capabilities** selecciona tu equipo de desarrollo.

Permisos ya configurados en `Info.plist`: Bluetooth, micrófono y reconocimiento de voz.

## Firmware ESP32 (BLE v2)

**IMPORTANTE**: La app iOS usa BLE (Bluetooth Low Energy), NO Bluetooth Clásico.

### Novedades del firmware v2:
- **Watchdog de movimiento**: requiere app v2.0+ (que envía latidos cada 300 ms). Con la app v1 la silla se detendría tras ~1.2 s de movimiento. Tras un disparo (`WDG`), ignora movimiento hasta recibir `S`.
- Con freno total activo se **ignoran** los comandos de movimiento, y el freno **se conserva al desconectarse** (antes se soltaba solo, peligroso en pendientes).
- Al perderse el enlace en movimiento, el PWM se corta **en seco** (sin rampa) y el re-anuncio BLE ya no bloquea el lazo de control.
- Los comandos BLE se **encolan** y se procesan en el lazo principal (sin carreras entre tareas).
- Notifica `RT:2.0` y `BRK:0/1` cada 5 s, y `BAT:n` si defines `BATTERY_ADC_PIN`.
- Los comandos y UUIDs son los mismos: **compatible con el cableado existente**.

### Instalación del firmware:
1. Abre `esp32_ble/ruedatec_ble.ino` en Arduino IDE
2. **Requiere ESP32 Arduino core 3.0+** (Gestor de tarjetas → esp32 ≥ 3.0); con core 2.x no compila
3. Selecciona tu placa ESP32 y puerto
4. Sube el firmware

## Protocolo de Comandos

| Comando | Acción |
|---------|--------|
| `F` | Avanzar |
| `B` | Retroceder |
| `L` | Girar izquierda |
| `R` | Girar derecha |
| `G` | Avanzar + izquierda |
| `I` | Avanzar + derecha |
| `H` | Retroceder + izquierda |
| `J` | Retroceder + derecha |
| `S` | Parar |
| `W` | Freno total ON |
| `w` | Freno total OFF |
| `1-9` | Ajustar velocidad (la app ya no envía `0`) |

Mientras hay movimiento, la app reenvía el comando de dirección cada 300 ms (latido del watchdog). Mensajes del ESP32 hacia la app: `RT:<versión>`, `BRK:<0|1>` (estado del freno), `BAT:<0-100>`, `WDG` (watchdog disparado; la app responde con `S`).

## Comandos de voz

| Di… | Acción |
|-----|--------|
| «adelante» / «avanza» | Avanzar (impulso) |
| «atrás» / «retrocede» | Retroceder (impulso) |
| «izquierda» / «derecha» | Girar (impulso) |
| «alto» / «para» / «stop» / «detente» | **Parar de inmediato** |
| «freno» | Freno total ON |
| «quitar freno» / «suelta freno» | Freno total OFF |
| «velocidad 1…9» | Fijar velocidad |
| «más rápido» / «más lento» | Subir/bajar velocidad |
| «emergencia» | Paro de emergencia + freno |

## Estructura del Proyecto

```
RuedaTec/
├── App/
│   └── RuedaTecApp.swift          # Entry point + paro de seguridad en background
├── Models/
│   ├── BluetoothManager.swift     # BLE, keepalive, reconexión, telemetría, log
│   ├── VoiceControlManager.swift  # Reconocimiento de voz + comandos seguros
│   ├── SettingsStore.swift        # Preferencias persistentes
│   ├── DriveDirection.swift       # Direcciones y comandos
│   ├── HapticsManager.swift       # Vibraciones centralizadas
│   └── ShakeDetector.swift        # Sacudida → paro de emergencia
├── Views/
│   ├── OnboardingView.swift       # Onboarding (5 páginas)
│   ├── HomeView.swift             # Conexión, reconexión rápida, radar
│   ├── ControlsView.swift         # Panel de control (voz, pad/joystick, e-stop)
│   ├── SettingsView.swift         # Ajustes
│   ├── ConsoleView.swift          # Consola de diagnóstico
│   ├── ManualView.swift           # Manual de usuario
│   └── Components/
│       ├── DPadView.swift         # Pad direccional táctil
│       ├── JoystickView.swift     # Joystick virtual
│       ├── SpeedControlView.swift # Control de velocidad
│       ├── VoiceControlView.swift # Panel de voz (mic, onda, transcripción)
│       └── IndicatorViews.swift   # Señal, batería, radar, cronómetro
├── Theme/
│   └── AppTheme.swift             # Sistema de diseño
├── Info.plist
└── Assets.xcassets/
```

## Publicación en App Store

1. Registra una cuenta de Apple Developer ($99/año)
2. Configura los certificados y perfiles de aprovisionamiento
3. En Xcode: **Product** → **Archive** → **Distribute App**
4. Completa la información en App Store Connect

## Para Android (futuro)

La app se puede portar a Android usando:
- **Kotlin + Jetpack Compose** (nativo)
- **Flutter** (multiplataforma)

El firmware ESP32 BLE es compatible con Android sin cambios.
