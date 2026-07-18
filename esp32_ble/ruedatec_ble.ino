/**
 * RuedaTec Pro - Firmware BLE v2 para ESP32
 *
 * REQUIERE: ESP32 Arduino core 3.0 o superior (API LEDC por pin y
 * getValue() devolviendo String). Con core 2.x no compila.
 *
 * Protocolo: Nordic UART Service (NUS)
 * - Service UUID:  6E400001-B5A3-F393-E0A9-E50E24DCCA9E
 * - RX Char UUID:  6E400002-B5A3-F393-E0A9-E50E24DCCA9E (app escribe aquí)
 * - TX Char UUID:  6E400003-B5A3-F393-E0A9-E50E24DCCA9E (ESP32 notifica aquí)
 *
 * Comandos (un solo carácter):
 *   F=Adelante  B=Atrás  L=Izquierda  R=Derecha  S=Parar
 *   G=Adelante-Izq  I=Adelante-Der  H=Atrás-Izq  J=Atrás-Der
 *   W=Freno ON  w=Freno OFF
 *   1-9=Velocidad (0 se acepta pero la app ya no lo envía)
 *
 * Mensajes hacia la app (notify): "RT:2.0" versión, "BRK:0/1" estado del
 * freno, "BAT:n" batería (opcional), "WDG" watchdog disparado.
 *
 * ── Novedades v2 ──
 * 1. WATCHDOG DE MOVIMIENTO: la app v2 reenvía la dirección activa cada
 *    300 ms como "latido". Si la silla está en movimiento y no llega ningún
 *    comando en WATCHDOG_MS, los motores se detienen solos Y se ignoran los
 *    comandos de movimiento hasta recibir una 'S' (la app la envía al
 *    procesar el aviso "WDG"). Esto protege contra caídas de la app, del
 *    enlace BLE o del teléfono.
 *    NOTA: requiere app v2.0+. La app v1 (que enviaba el comando una sola
 *    vez) provocaría paradas tras ~1.2 s de movimiento.
 * 2. SEGURIDAD DE FRENO: con el freno total activo se ignoran los comandos
 *    de movimiento (antes quedaban "en cola" y la silla arrancaba sola al
 *    soltar el freno). El freno SE CONSERVA al perderse la conexión: si la
 *    silla quedó frenada en una rampa y el teléfono muere, no se suelta.
 *    El estado real se notifica a la app con "BRK:" al reconectar.
 * 3. PARO INMEDIATO EN DESCONEXIÓN: al perderse el enlace en movimiento,
 *    el PWM se corta en seco (sin rampa) y el re-anuncio BLE ya no bloquea
 *    el lazo de control con delay().
 * 4. Los comandos BLE se encolan y se procesan en loop(): sin carreras
 *    entre la tarea Bluetooth y el lazo de control.
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#if !defined(ESP_ARDUINO_VERSION_MAJOR) || ESP_ARDUINO_VERSION_MAJOR < 3
#error "Este firmware requiere ESP32 Arduino core 3.x (Herramientas > Placa > Gestor de tarjetas > esp32 >= 3.0)"
#endif

#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

#define FIRMWARE_VERSION "2.0"

// ── Watchdog de movimiento ──
// La app v2 reenvía el comando de dirección cada 300 ms mientras se mantiene
// presionado. Con margen 4x: si no llega nada en 1200 ms, paramos.
const unsigned long WATCHDOG_MS = 1200;

// ── Telemetría de batería (opcional) ──
// Descomenta y ajusta si el hardware tiene divisor de tensión hacia un ADC:
// #define BATTERY_ADC_PIN 34
// const float BATTERY_VOLTAGE_MIN = 21.0;  // 0%  (ej. pack 24V)
// const float BATTERY_VOLTAGE_MAX = 29.4;  // 100%
// const float BATTERY_DIVIDER_RATIO = 11.0; // (R1+R2)/R2 del divisor

// ── Pines de motores ──
const int motorP1     = 18;  // PWM motor 1 (antes GPIO 12 - strapping pin)
const int motorDir1   = 27;  // Dirección motor 1 - OK
const int motorBrake1 = 25;  // Freno motor 1 - OK

const int motorP2     = 19;  // PWM motor 2 (antes GPIO 14 - pulso al boot)
const int motorDir2   = 26;  // Dirección motor 2 - OK
const int motorBrake2 = 32;  // Freno motor 2 - OK

// ── Estado ──
BLECharacteristic *pTxCharacteristic;
volatile bool deviceConnected = false;
bool oldDeviceConnected       = false;

int  porcentajeCurva   = 25;    // Rueda lenta va al 25% en diagonales
bool frenoTotal        = false;

bool avanzar    = false;
bool retroceder = false;
bool izquierda  = false;
bool derecha    = false;

// Tras un disparo del watchdog se ignoran los comandos de movimiento hasta
// recibir una 'S' (la app la envía al ver el aviso "WDG").
bool watchdogTripped = false;

// ── Cola de comandos ──
// onWrite corre en la tarea BLE y loop() en otra: los comandos se encolan
// aquí (un solo productor, un solo consumidor) y se procesan en loop(),
// evitando carreras sobre los flags de movimiento y lastCommandMs.
volatile char    cmdQueue[16];
volatile uint8_t cmdHead = 0;
volatile uint8_t cmdTail = 0;

// ── Soft start & smooth transitions ──
int velocidadObjetivo  = 255;   // Velocidad que el usuario eligió
int velocidadActual    = 255;   // Velocidad que sube/baja suavemente

int pwmObjetivoM1  = 0;        // PWM destino motor 1
int pwmObjetivoM2  = 0;        // PWM destino motor 2
int pwmActualM1    = 0;        // PWM actual motor 1 (rampa)
int pwmActualM2    = 0;        // PWM actual motor 2 (rampa)

const int RAMP_STEP      = 5;  // Incremento PWM por ciclo (arranque suave)
const int RAMP_DOWN_STEP = 10; // Decremento PWM por ciclo (frenado más rápido)
const int VEL_STEP       = 3;  // Incremento para transición entre niveles
const int RAMP_MS        = 10; // Milisegundos entre actualizaciones de rampa

unsigned long lastRampUpdate   = 0;
unsigned long lastCommandMs    = 0;   // Último comando procesado (watchdog)
unsigned long connectedAtMs    = 0;
unsigned long lastTelemetryMs  = 0;
unsigned long disconnectedAtMs = 0;
bool needsReadvertise          = false;

// ── BLE Callbacks ──
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) override {
    deviceConnected = true;
    connectedAtMs = millis();
    lastTelemetryMs = 0;
    watchdogTripped = false;
    Serial.println("Cliente conectado");
  }

  void onDisconnect(BLEServer *pServer) override {
    deviceConnected = false;
    Serial.println("Cliente desconectado");
    // El paro de motores y el re-anuncio se manejan en loop() para no tocar
    // el estado de control desde la tarea BLE. IMPORTANTE: el freno total
    // NO se suelta aquí: si la silla quedó frenada en una pendiente, debe
    // seguir frenada aunque el teléfono muera.
  }
};

void processCommand(char comando);
void ajustarVelocidad(char comando);
void calcularObjetivos();
void actualizarRampa();
void drenarComandos();
void revisarWatchdog();
void manejarDesconexion();
void enviarTelemetria();
void notificar(const String &mensaje);

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    String rxValue = pCharacteristic->getValue();
    for (unsigned int i = 0; i < rxValue.length(); i++) {
      uint8_t next = (cmdHead + 1) & 15;
      if (next != cmdTail) {          // si la cola está llena, se descarta
        cmdQueue[cmdHead] = rxValue[i];
        cmdHead = next;
      }
    }
  }
};

// ── Setup ──
void setup() {
  Serial.begin(115200);

  pinMode(motorDir1, OUTPUT);
  pinMode(motorBrake1, OUTPUT);
  pinMode(motorDir2, OUTPUT);
  pinMode(motorBrake2, OUTPUT);

  ledcAttach(motorP1, 5000, 8);
  ledcAttach(motorP2, 5000, 8);
  ledcWrite(motorP1, 0);
  ledcWrite(motorP2, 0);

#ifdef BATTERY_ADC_PIN
  pinMode(BATTERY_ADC_PIN, INPUT);
#endif

  // Inicializar BLE
  BLEDevice::init("RuedaTecPro");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pTxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_TX,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pTxCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_RX,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pRxCharacteristic->setCallbacks(new RxCallbacks());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();

  Serial.println("RuedaTec BLE v2 listo - esperando conexión");
}

// ── Loop ──
void loop() {
  drenarComandos();
  revisarWatchdog();
  manejarDesconexion();
  calcularObjetivos();
  actualizarRampa();
  enviarTelemetria();
}

// ── Procesa los comandos encolados por la tarea BLE ──
void drenarComandos() {
  while (cmdTail != cmdHead) {
    char comando = cmdQueue[cmdTail];
    cmdTail = (cmdTail + 1) & 15;
    lastCommandMs = millis();
    processCommand(comando);
  }
}

// ── Watchdog: si hay movimiento y la app dejó de "latir", parar ──
void revisarWatchdog() {
  bool enMovimiento = avanzar || retroceder || izquierda || derecha;
  if (enMovimiento && (millis() - lastCommandMs > WATCHDOG_MS)) {
    avanzar = false;
    retroceder = false;
    izquierda = false;
    derecha = false;
    watchdogTripped = true;   // se ignora todo movimiento hasta recibir 'S'
    Serial.println("WATCHDOG: sin latido de la app, motores detenidos");
    notificar("WDG");
  }
}

// ── Desconexión: paro inmediato + re-anuncio sin bloquear ──
void manejarDesconexion() {
  if (!deviceConnected && oldDeviceConnected) {
    oldDeviceConnected = false;
    // Paro en seco: una pérdida de enlace no merece rampa suave.
    avanzar = false;
    retroceder = false;
    izquierda = false;
    derecha = false;
    watchdogTripped = false;
    pwmObjetivoM1 = 0; pwmObjetivoM2 = 0;
    pwmActualM1 = 0;   pwmActualM2 = 0;
    ledcWrite(motorP1, 0);
    ledcWrite(motorP2, 0);
    // (frenoTotal se conserva tal cual estaba)
    disconnectedAtMs = millis();
    needsReadvertise = true;
  }

  if (needsReadvertise && millis() - disconnectedAtMs > 500) {
    needsReadvertise = false;
    BLEDevice::startAdvertising();
    Serial.println("Re-anunciando BLE");
  }

  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = true;
  }
}

// ── Telemetría ──
// RT: y BRK: se repiten cada 5 s: una sola notificación al conectar podría
// perderse si la app aún no se había suscrito a las notificaciones.
void enviarTelemetria() {
  if (!deviceConnected) return;
  unsigned long now = millis();
  if (now - connectedAtMs < 1500) return;
  if (lastTelemetryMs != 0 && now - lastTelemetryMs < 5000) return;
  lastTelemetryMs = now;

  notificar(String("RT:") + FIRMWARE_VERSION);
  notificar(String("BRK:") + (frenoTotal ? "1" : "0"));

#ifdef BATTERY_ADC_PIN
  // Promedio de 8 lecturas del ADC (12 bits, atenuación por defecto ~3.3V)
  long sum = 0;
  for (int i = 0; i < 8; i++) sum += analogRead(BATTERY_ADC_PIN);
  float adcVolts = (sum / 8.0) / 4095.0 * 3.3;
  float packVolts = adcVolts * BATTERY_DIVIDER_RATIO;
  float pct = (packVolts - BATTERY_VOLTAGE_MIN)
            / (BATTERY_VOLTAGE_MAX - BATTERY_VOLTAGE_MIN) * 100.0;
  int nivel = constrain((int)pct, 0, 100);
  notificar(String("BAT:") + nivel);
#endif
}

void notificar(const String &mensaje) {
  if (!deviceConnected || pTxCharacteristic == nullptr) return;
  pTxCharacteristic->setValue(mensaje.c_str());
  pTxCharacteristic->notify();
}

// ── Procesamiento de comandos ──
void processCommand(char comando) {
  bool esMovimiento = (comando == 'F' || comando == 'B' || comando == 'L' ||
                       comando == 'R' || comando == 'G' || comando == 'I' ||
                       comando == 'H' || comando == 'J');

  // v2: con freno total activo se ignoran los comandos de movimiento.
  // Así la silla no "recuerda" una dirección y arranca sola al soltar el freno.
  if (frenoTotal && esMovimiento) {
    return;
  }
  // Tras un disparo del watchdog, solo una 'S' rearma el movimiento.
  if (watchdogTripped && esMovimiento) {
    return;
  }

  switch (comando) {
    case 'F':
      avanzar = true; retroceder = false; izquierda = false; derecha = false;
      break;
    case 'B':
      avanzar = false; retroceder = true; izquierda = false; derecha = false;
      break;
    case 'L':
      avanzar = false; retroceder = false; izquierda = true; derecha = false;
      break;
    case 'R':
      avanzar = false; retroceder = false; izquierda = false; derecha = true;
      break;
    case 'S':
      avanzar = false; retroceder = false; izquierda = false; derecha = false;
      watchdogTripped = false;
      break;
    case 'G':
      avanzar = true; retroceder = false; izquierda = true; derecha = false;
      break;
    case 'I':
      avanzar = true; retroceder = false; izquierda = false; derecha = true;
      break;
    case 'H':
      avanzar = false; retroceder = true; izquierda = true; derecha = false;
      break;
    case 'J':
      avanzar = false; retroceder = true; izquierda = false; derecha = true;
      break;
    case 'W':
      frenoTotal = true;
      avanzar = false; retroceder = false; izquierda = false; derecha = false;
      break;
    case 'w':
      frenoTotal = false;
      break;
    default:
      ajustarVelocidad(comando);
  }
}

void ajustarVelocidad(char comando) {
  if (comando >= '0' && comando <= '9') {
    velocidadObjetivo = map(comando - '0', 0, 9, 0, 255);
    Serial.print("Velocidad objetivo: ");
    Serial.println(velocidadObjetivo);
  }
}

// ── Calcular PWM objetivo para cada motor ──
void calcularObjetivos() {
  int velCurva = velocidadActual * porcentajeCurva / 100;

  if (frenoTotal) {
    digitalWrite(motorBrake1, HIGH);
    digitalWrite(motorBrake2, HIGH);
    pwmObjetivoM1 = 0;
    pwmObjetivoM2 = 0;
    pwmActualM1 = 0;
    pwmActualM2 = 0;
    ledcWrite(motorP1, 0);
    ledcWrite(motorP2, 0);
    return;
  }

  digitalWrite(motorBrake1, LOW);
  digitalWrite(motorBrake2, LOW);

  if (avanzar) {
    if (izquierda) {
      digitalWrite(motorDir1, LOW);
      digitalWrite(motorDir2, HIGH);
      pwmObjetivoM1 = velCurva;
      pwmObjetivoM2 = velocidadActual;
    } else if (derecha) {
      digitalWrite(motorDir1, LOW);
      digitalWrite(motorDir2, HIGH);
      pwmObjetivoM1 = velocidadActual;
      pwmObjetivoM2 = velCurva;
    } else {
      digitalWrite(motorDir1, LOW);
      digitalWrite(motorDir2, HIGH);
      pwmObjetivoM1 = velocidadActual;
      pwmObjetivoM2 = velocidadActual;
    }
  } else if (retroceder) {
    if (izquierda) {
      digitalWrite(motorDir1, HIGH);
      digitalWrite(motorDir2, LOW);
      pwmObjetivoM1 = velCurva;
      pwmObjetivoM2 = velocidadActual;
    } else if (derecha) {
      digitalWrite(motorDir1, HIGH);
      digitalWrite(motorDir2, LOW);
      pwmObjetivoM1 = velocidadActual;
      pwmObjetivoM2 = velCurva;
    } else {
      digitalWrite(motorDir1, HIGH);
      digitalWrite(motorDir2, LOW);
      pwmObjetivoM1 = velocidadActual;
      pwmObjetivoM2 = velocidadActual;
    }
  } else if (izquierda) {
    digitalWrite(motorDir1, HIGH);
    digitalWrite(motorDir2, HIGH);
    pwmObjetivoM1 = velocidadActual;
    pwmObjetivoM2 = velocidadActual;
  } else if (derecha) {
    digitalWrite(motorDir1, LOW);
    digitalWrite(motorDir2, LOW);
    pwmObjetivoM1 = velocidadActual;
    pwmObjetivoM2 = velocidadActual;
  } else {
    pwmObjetivoM1 = 0;
    pwmObjetivoM2 = 0;
  }
}

// ── Rampa suave: mueve PWM actual hacia objetivo gradualmente ──
void actualizarRampa() {
  unsigned long now = millis();
  if (now - lastRampUpdate < RAMP_MS) return;
  lastRampUpdate = now;

  // Transición suave entre niveles de velocidad
  if (velocidadActual < velocidadObjetivo) {
    velocidadActual = min(velocidadActual + VEL_STEP, velocidadObjetivo);
  } else if (velocidadActual > velocidadObjetivo) {
    velocidadActual = max(velocidadActual - VEL_STEP, velocidadObjetivo);
  }

  // Rampa motor 1: sube lento, baja rápido
  if (pwmActualM1 < pwmObjetivoM1) {
    pwmActualM1 = min(pwmActualM1 + RAMP_STEP, pwmObjetivoM1);
  } else if (pwmActualM1 > pwmObjetivoM1) {
    pwmActualM1 = max(pwmActualM1 - RAMP_DOWN_STEP, pwmObjetivoM1);
  }

  // Rampa motor 2: sube lento, baja rápido
  if (pwmActualM2 < pwmObjetivoM2) {
    pwmActualM2 = min(pwmActualM2 + RAMP_STEP, pwmObjetivoM2);
  } else if (pwmActualM2 > pwmObjetivoM2) {
    pwmActualM2 = max(pwmActualM2 - RAMP_DOWN_STEP, pwmObjetivoM2);
  }

  ledcWrite(motorP1, pwmActualM1);
  ledcWrite(motorP2, pwmActualM2);
}
