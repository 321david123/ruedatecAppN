import Foundation
import Speech
import AVFoundation
import Combine

/// Control por voz de la silla usando reconocimiento de voz continuo.
///
/// Diseño de seguridad:
/// - Las palabras de PARO ("alto", "para", "stop"…) se ejecutan de inmediato
///   sobre resultados parciales y SIEMPRE se procesan, incluso mientras la app
///   está hablando una confirmación.
/// - Los comandos de movimiento son impulsos: la silla avanza durante
///   `settings.voiceMoveDuration` segundos y se detiene sola, salvo que el
///   usuario active el modo continuo explícitamente en Ajustes.
/// - Anti-eco por contenido: mientras suena una confirmación sintetizada (y un
///   margen después), las palabras de ESA confirmación se descartan para que
///   la app no obedezca su propia voz. Las demás palabras del usuario sí se
///   procesan.
/// - Tras un paro hay un periodo de calma: los comandos de movimiento se
///   descartan brevemente para que «para atrás» no anuncie "Alto" y luego
///   retroceda solo.
///
/// Robustez del pipeline (aprendido en dispositivo real):
/// - Reproducir la confirmación TTS puede reconfigurar el motor de audio y
///   matar el tap del micrófono EN SILENCIO: sin buffers no hay resultados ni
///   errores, y la escucha parece viva pero está muerta. Por eso hay un
///   watchdog de vitalidad (si no llegan buffers en 2 s, se reinicia la
///   sesión) además de observar AVAudioEngineConfigurationChange y los
///   cambios de ruta de audio.
final class VoiceControlManager: NSObject, ObservableObject {

    // MARK: - Published
    @Published var isListening = false
    @Published var permissionDenied = false
    @Published var recognizerAvailable = true
    @Published var transcript = ""
    @Published var lastAction: String?
    @Published var audioLevel: Double = 0

    // MARK: - Dependencies
    private let bluetooth: BluetoothManager
    private let settings: SettingsStore

    // MARK: - Speech
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Se crea un motor NUEVO en cada sesión: un motor viejo conserva el
    /// formato de hardware anterior (p. ej. 48 kHz) aunque al activar la
    /// sesión el micrófono real cambie (24 kHz con altavoz/Bluetooth), e
    /// installTap con ese formato desfasado lanza una excepción
    /// irrecuperable ("Failed to create tap due to format mismatch").
    private var audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var engineRetryCount = 0

    /// Generación de la sesión de reconocimiento. Los callbacks de tareas
    /// canceladas (generación vieja) se ignoran por completo: sin esto, el
    /// error de cancelación de la tarea anterior dispararía reinicios en
    /// bucle y los resultados viejos podrían re-ejecutar comandos.
    private var sessionGeneration = 0

    private var processedWordCount = 0
    private var pulseWorkItem: DispatchWorkItem?
    private var sessionRestartWorkItem: DispatchWorkItem?
    private var lastActionClearWorkItem: DispatchWorkItem?
    private var echoFilterClearWorkItem: DispatchWorkItem?
    private var lastAudioLevelUpdate = Date.distantPast

    /// Watchdog de vitalidad del micrófono.
    private var livenessTimer: Timer?
    private var lastBufferAt = Date.distantPast

    /// Palabras de la confirmación que la app está hablando ahora mismo
    /// (normalizadas). Se descartan si el micrófono las vuelve a oír.
    private var echoFilterWords: Set<String> = []

    /// Tras un paro, los comandos de movimiento se ignoran hasta este momento.
    private var movementQuietUntil = Date.distantPast

    /// Última dirección cardinal reconocida, para combinar en diagonales
    /// ("adelante… izquierda" → adelante-izquierda) mientras la silla aún se
    /// mueve en la primera dirección.
    private var lastDirectionWord: (direction: DriveDirection, date: Date)?
    private let diagonalWindow: TimeInterval = 2.5
    private let postStopQuietPeriod: TimeInterval = 0.8

    // MARK: - Vocabulario (normalizado: minúsculas y sin acentos)
    private let stopWords: Set<String> = [
        "alto", "para", "parar", "parate", "detente", "deten", "stop",
        "quieto", "basta", "espera", "halt"
    ]
    private let emergencyWords: Set<String> = ["emergencia", "emergency", "auxilio"]
    private let forwardWords: Set<String> = [
        "adelante", "avanza", "avanzar", "avance", "forward", "frente", "vamos"
    ]
    private let backWords: Set<String> = [
        "atras", "retrocede", "retroceder", "reversa", "back", "backward", "backwards"
    ]
    private let leftWords: Set<String> = ["izquierda", "left"]
    private let rightWords: Set<String> = ["derecha", "right"]
    private let brakeOnWords: Set<String> = ["freno", "frena", "brake"]
    private let brakeOffPhrases: [[String]] = [
        ["quitar", "freno"], ["quita", "freno"], ["suelta", "freno"],
        ["soltar", "freno"], ["sin", "freno"], ["libera", "freno"],
        ["release", "brake"], ["suelta", "el", "freno"], ["quita", "el", "freno"]
    ]
    private let fasterWords: Set<String> = ["rapido", "rapida", "acelera", "faster"]
    private let slowerWords: Set<String> = ["lento", "lenta", "despacio", "slower"]
    private let speedKeywords: Set<String> = ["velocidad", "speed"]
    private let numberWords: [String: Int] = [
        "cero": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4,
        "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9,
        "zero": 1, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "0": 1, "1": 1, "2": 2, "3": 3, "4": 4,
        "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
        "maxima": 9, "maximo": 9, "max": 9, "minima": 1, "minimo": 1
    ]

    /// Sesgo del reconocedor hacia nuestro vocabulario: mejora mucho la
    /// precisión con palabras sueltas como "izquierda" o "freno".
    private let contextualVocabulary = [
        "adelante", "avanza", "atrás", "retrocede", "reversa",
        "izquierda", "derecha", "alto", "para", "detente", "stop",
        "freno", "quitar freno", "suelta el freno",
        "velocidad", "más rápido", "más lento", "despacio",
        "emergencia", "quieto", "basta",
        "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve"
    ]

    // MARK: - Init
    init(bluetooth: BluetoothManager, settings: SettingsStore) {
        self.bluetooth = bluetooth
        self.settings = settings
        super.init()
        synthesizer.delegate = self
        let locale = Locale(identifier: "es-MX")
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        recognizerAvailable = recognizer != nil

        let center = NotificationCenter.default
        // Una llamada telefónica u otra interrupción de audio mata el motor
        // de reconocimiento en silencio: detener el movimiento por seguridad.
        center.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        // El motor de audio se reconfigura (p. ej. al reproducir la
        // confirmación TTS o al conectar audífonos): hay que rearmar el tap.
        // object: nil porque el motor se recrea en cada sesión.
        center.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        livenessTimer?.invalidate()
    }

    // MARK: - Public API
    func toggle() {
        isListening ? stop() : start()
    }

    func start() {
        guard !isListening else { return }
        requestPermissions { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.permissionDenied = true
                return
            }
            self.permissionDenied = false
            self.isListening = true
            self.transcript = ""
            self.lastAction = nil
            self.echoFilterWords.removeAll()
            self.engineRetryCount = 0
            self.beginRecognitionSession()
            self.startLivenessWatchdog()
            Haptics.success()
        }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        stopLivenessWatchdog()
        endRecognitionSession()
        failSafeStopIfVoiceDriving()
        synthesizer.stopSpeaking(at: .immediate)
        echoFilterWords.removeAll()
        transcript = ""
        audioLevel = 0
        Haptics.tap(.medium)
    }

    // MARK: - Permissions
    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            DispatchQueue.main.async {
                guard speechStatus == .authorized else {
                    completion(false)
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { micGranted in
                    DispatchQueue.main.async {
                        completion(micGranted)
                    }
                }
            }
        }
    }

    // MARK: - Recognition Session
    private func beginRecognitionSession() {
        endRecognitionSession(keepListeningFlag: true)

        guard let recognizer, recognizer.isAvailable else {
            recognizerAvailable = false
            isListening = false
            return
        }
        recognizerAvailable = true

        sessionGeneration += 1
        let generation = sessionGeneration

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // Motor nuevo DESPUÉS de activar la sesión: así su nodo de entrada
            // refleja el formato real del hardware y el tap no puede fallar
            // por desfase de formatos (crash en dispositivo real).
            audioEngine = AVAudioEngine()
            let inputNode = audioEngine.inputNode
            let hwFormat = inputNode.outputFormat(forBus: 0)
            guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
                // Reconfiguración de audio pendiente: reintentar en breve en
                // lugar de instalar un tap condenado a fallar.
                retryOrGiveUp()
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Sesgo hacia los comandos de la silla: sin esto, palabras sueltas
            // como "izquierda" se transcriben mal con frecuencia.
            request.contextualStrings = contextualVocabulary
            self.request = request

            // format: nil deja que el motor use el formato vigente del bus,
            // en lugar de un formato consultado antes que puede estar viejo.
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                self?.lastBufferAt = Date()
                self?.request?.append(buffer)
                self?.updateAudioLevel(from: buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            lastBufferAt = Date()
            engineRetryCount = 0

            processedWordCount = 0
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, generation == self.sessionGeneration else { return }
                    self.handleRecognition(result: result, error: error)
                }
            }

            // El reconocimiento continuo tiene un límite (~1 min): se reinicia solo.
            scheduleSessionRestart(after: 50)
        } catch {
            audioLevel = 0
            retryOrGiveUp()
        }
    }

    /// El arranque del audio puede fallar de forma transitoria (cambio de
    /// configuración pendiente, ruta cambiando). Se reintenta unas veces
    /// antes de rendirse, y al rendirse la silla queda detenida si la voz
    /// era la dueña del movimiento.
    private func retryOrGiveUp() {
        if engineRetryCount < 4 {
            engineRetryCount += 1
            scheduleSessionRestart(after: 0.5)
        } else {
            engineRetryCount = 0
            isListening = false
            audioLevel = 0
            failSafeStopIfVoiceDriving()
            showAction("No se pudo iniciar el micrófono")
        }
    }

    private func endRecognitionSession(keepListeningFlag: Bool = false) {
        // Invalida los callbacks pendientes de la tarea que vamos a cancelar.
        sessionGeneration += 1
        sessionRestartWorkItem?.cancel()
        sessionRestartWorkItem = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        if !keepListeningFlag {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func scheduleSessionRestart(after seconds: TimeInterval) {
        sessionRestartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isListening else { return }
            self.beginRecognitionSession()
        }
        sessionRestartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    // MARK: - Liveness Watchdog
    /// Si el micrófono deja de entregar buffers (el TTS reconfiguró el motor,
    /// cambió la ruta de audio, etc.), la sesión se rearma sola en ~2 s.
    private func startLivenessWatchdog() {
        livenessTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isListening else { return }
            if Date().timeIntervalSince(self.lastBufferAt) > 2.0 {
                self.lastBufferAt = Date()   // evita reinicios en cascada
                self.beginRecognitionSession()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        livenessTimer = timer
    }

    private func stopLivenessWatchdog() {
        livenessTimer?.invalidate()
        livenessTimer = nil
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            if !text.isEmpty {
                transcript = text
            }

            // Algunos modos del reconocedor devuelven varios términos por
            // segmento: se separa por espacios para no perder comandos.
            let words = result.bestTranscription.segments.flatMap { segment in
                Self.normalize(segment.substring)
                    .split(separator: " ")
                    .map(String.init)
            }
            // El reconocedor puede REVISAR el transcript y reducir el número de
            // palabras; sin este ajuste, las palabras nuevas (incluido "alto")
            // quedarían por debajo del contador y se perderían para siempre.
            processedWordCount = min(processedWordCount, words.count)
            if words.count > processedWordCount {
                let newWords = Array(words[processedWordCount...])
                processedWordCount = words.count
                process(newWords: newWords, allWords: words)
            }
        }

        if error != nil || (result?.isFinal ?? false) {
            // Reinicia la sesión si seguimos en modo escucha. Solo llega aquí
            // la tarea vigente (los callbacks viejos se filtran por generación).
            if isListening {
                sessionRestartWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    guard let self, self.isListening else { return }
                    self.beginRecognitionSession()
                }
                sessionRestartWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
            }
        }
    }

    // MARK: - Command Processing
    private func process(newWords rawNewWords: [String], allWords: [String]) {
        // 1) PARO: prioridad absoluta. Se evalúa ANTES que cualquier filtro:
        //    un "alto" del usuario jamás debe descartarse. (El eco de la
        //    confirmación "Alto" solo repetiría el paro: inofensivo.)
        if rawNewWords.contains(where: { stopWords.contains($0) }) {
            executeStop()
            return
        }
        if rawNewWords.contains(where: { emergencyWords.contains($0) }) {
            executeEmergency()
            return
        }

        // 2) Anti-eco: descarta las palabras de la confirmación que la app
        //    está pronunciando (o acaba de pronunciar). Se consumen aquí y
        //    ya no pueden ejecutarse nunca, ni ahora ni en un lote futuro.
        let newWords = rawNewWords.filter { !echoFilterWords.contains($0) }
        guard !newWords.isEmpty else { return }

        // 3) Frases de varias palabras (quitar freno, velocidad N…)
        if matchBrakeOff(in: allWords, newCount: newWords.count) { return }
        if matchSpeedSet(in: allWords, newCount: newWords.count) { return }

        // 4) Palabras sueltas, en orden de llegada.
        for word in newWords {
            if brakeOnWords.contains(word) {
                executeBrake(on: true)
                return
            }
            if fasterWords.contains(word) {
                executeSpeedDelta(+1)
                return
            }
            if slowerWords.contains(word) {
                executeSpeedDelta(-1)
                return
            }
            if let direction = direction(for: word) {
                executeMove(direction)
                return
            }
        }
    }

    private func direction(for word: String) -> DriveDirection? {
        let base: DriveDirection?
        if forwardWords.contains(word) { base = .forward }
        else if backWords.contains(word) { base = .back }
        else if leftWords.contains(word) { base = .left }
        else if rightWords.contains(word) { base = .right }
        else { base = nil }

        guard let base else { return nil }

        // Combina en diagonal ("adelante… izquierda") SOLO si la silla sigue
        // moviéndose en la primera dirección; si ya se detuvo, la nueva
        // palabra es un comando independiente.
        if let last = lastDirectionWord,
           Date().timeIntervalSince(last.date) < diagonalWindow,
           bluetooth.activeDirection == last.direction,
           let diagonal = DriveDirection.combining(last.direction, base) {
            lastDirectionWord = (base, Date())
            return diagonal
        }
        lastDirectionWord = (base, Date())
        return base
    }

    /// Busca frases de "quitar freno". Solo acepta coincidencias que incluyan
    /// al menos una palabra NUEVA: sin esto, la frase ya ejecutada del lote
    /// anterior volvería a coincidir y se tragaría el comando siguiente.
    private func matchBrakeOff(in words: [String], newCount: Int) -> Bool {
        let window = Array(words.suffix(newCount + 2))
        for phrase in brakeOffPhrases {
            if window.count >= phrase.count {
                for start in 0...(window.count - phrase.count) {
                    let end = start + phrase.count
                    guard end > window.count - newCount else { continue }
                    if Array(window[start..<end]) == phrase {
                        executeBrake(on: false)
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Busca "velocidad <número>". Igual que arriba: la coincidencia debe
    /// terminar dentro de las palabras nuevas.
    private func matchSpeedSet(in words: [String], newCount: Int) -> Bool {
        let window = Array(words.suffix(newCount + 2))
        for (index, word) in window.enumerated() {
            let end = index + 2
            guard end > window.count - newCount, index + 1 < window.count else { continue }
            if speedKeywords.contains(word), let value = numberWords[window[index + 1]] {
                executeSpeedSet(value)
                return true
            }
            // También "máxima velocidad" / "mínima velocidad"
            if (word == "maxima" || word == "minima"), speedKeywords.contains(window[index + 1]) {
                executeSpeedSet(word == "maxima" ? 9 : 1)
                return true
            }
        }
        return false
    }

    // MARK: - Command Execution
    private func executeStop() {
        pulseWorkItem?.cancel()
        lastDirectionWord = nil
        // Calma post-paro: en es-MX "para atrás" significa "hacia atrás";
        // sin esto, el "atrás" que sigue al "para" relanzaría la silla
        // justo después de anunciar "Alto".
        movementQuietUntil = Date().addingTimeInterval(postStopQuietPeriod)
        bluetooth.setDirection(nil)
        showAction("Alto")
        speak("Alto")
        Haptics.tap(.heavy)
    }

    private func executeEmergency() {
        pulseWorkItem?.cancel()
        lastDirectionWord = nil
        movementQuietUntil = Date().addingTimeInterval(postStopQuietPeriod)
        bluetooth.emergencyStop()
        showAction("Paro de emergencia")
        speak("Paro de emergencia")
    }

    private func executeMove(_ direction: DriveDirection) {
        guard Date() >= movementQuietUntil else { return }
        guard bluetooth.isConnected else {
            showAction("Sin conexión")
            return
        }
        guard !bluetooth.brakeActive else {
            showAction("Freno activado")
            speak("Freno activado")
            return
        }
        // Si el usuario está conduciendo con la mano, la voz no interfiere.
        guard bluetooth.setDirection(direction, source: .voice) else { return }
        showAction(direction.label)
        speak(direction.spokenConfirmation)
        Haptics.tap(.medium)

        // Impulso de seguridad: auto-paro tras la duración configurada.
        pulseWorkItem?.cancel()
        if !settings.voiceContinuousMovement {
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // Solo detiene el movimiento si la voz sigue siendo la dueña:
                // si el usuario tomó el pad, el impulso ya no aplica.
                if self.bluetooth.activeDirection == direction,
                   self.bluetooth.movementSource == .voice {
                    self.bluetooth.setDirection(nil)
                }
            }
            pulseWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.voiceMoveDuration, execute: item)
        }
    }

    private func executeBrake(on: Bool) {
        bluetooth.setBrake(on)
        showAction(on ? "Freno activado" : "Freno desactivado")
        speak(on ? "Freno" : "Freno quitado")
        Haptics.tap(.heavy)
    }

    private func executeSpeedDelta(_ delta: Int) {
        let newSpeed = max(1, min(9, bluetooth.currentSpeed + delta))
        bluetooth.setSpeed(newSpeed)
        showAction("Velocidad \(newSpeed)")
        speak(delta > 0 ? "Más rápido" : "Más lento")
        Haptics.tap(.light)
    }

    private func executeSpeedSet(_ value: Int) {
        let clamped = max(1, min(9, value))
        bluetooth.setSpeed(clamped)
        showAction("Velocidad \(clamped)")
        speak("Velocidad \(clamped)")
        Haptics.tap(.light)
    }

    private func showAction(_ label: String) {
        lastAction = label
        lastActionClearWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.lastAction = nil
        }
        lastActionClearWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
    }

    // MARK: - Fail-safe
    /// Si la voz es la dueña del movimiento y el canal de voz muere
    /// (interrupción de audio, error del motor), la silla se detiene.
    private func failSafeStopIfVoiceDriving() {
        pulseWorkItem?.cancel()
        if bluetooth.movementSource == .voice {
            bluetooth.setDirection(nil)
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        if type == .began {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isListening else { return }
                self.isListening = false
                self.stopLivenessWatchdog()
                self.endRecognitionSession()
                self.failSafeStopIfVoiceDriving()
                self.audioLevel = 0
                self.showAction("Voz interrumpida")
            }
        }
    }

    /// El motor de audio se reconfiguró (típicamente al arrancar el TTS o al
    /// (des)conectar audífonos): el tap del micrófono queda muerto y hay que
    /// levantar la sesión de nuevo.
    @objc private func handleEngineConfigurationChange(_ notification: Notification) {
        // Solo interesa NUESTRO motor: el sintetizador de voz usa el suyo
        // propio y también emite esta notificación.
        guard (notification.object as? AVAudioEngine) === audioEngine else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isListening else { return }
            self.sessionRestartWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.isListening else { return }
                self.beginRecognitionSession()
            }
            self.sessionRestartWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange:
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isListening else { return }
                self.sessionRestartWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    guard let self, self.isListening else { return }
                    self.beginRecognitionSession()
                }
                self.sessionRestartWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
            }
        default:
            break
        }
    }

    // MARK: - Speech Synthesis (confirmaciones con filtro anti-eco)
    private func speak(_ text: String) {
        guard settings.voiceConfirmations else { return }

        // Registra las palabras de esta confirmación: si el micrófono las
        // vuelve a oír (eco de la propia app), se descartan por contenido.
        var words = Set(text.split(separator: " ").map { Self.normalize(String($0)) })
        for word in words {
            if let digit = Int(word), let spelled = spelledNumber(digit) {
                words.insert(spelled)
            }
        }
        echoFilterWords.formUnion(words)
        scheduleEchoFilterClear(after: 4.0)   // failsafe si didFinish nunca llega

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-MX")
            ?? AVSpeechSynthesisVoice(language: "es-ES")
        utterance.rate = 0.52
        utterance.volume = 0.9
        synthesizer.speak(utterance)
    }

    private func scheduleEchoFilterClear(after seconds: TimeInterval) {
        echoFilterClearWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.echoFilterWords.removeAll()
        }
        echoFilterClearWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func spelledNumber(_ digit: Int) -> String? {
        let names = ["cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve"]
        guard (0...9).contains(digit) else { return nil }
        return names[digit]
    }

    // MARK: - Audio Level (forma de onda)
    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastAudioLevelUpdate) > 0.05 else { return }
        lastAudioLevelUpdate = now

        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        // Escala logarítmica aproximada a 0…1.
        let level = min(1.0, max(0.0, Double(rms) * 18.0))
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isListening else { return }
            self.audioLevel = self.audioLevel * 0.6 + level * 0.4
        }
    }

    // MARK: - Normalization
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension VoiceControlManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Mantiene el filtro anti-eco un momento más: el reconocedor puede
        // entregar el eco con retraso, incluso después de que la voz termine.
        if !synthesizer.isSpeaking {
            scheduleEchoFilterClear(after: 1.5)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if !synthesizer.isSpeaking {
            scheduleEchoFilterClear(after: 1.0)
        }
    }
}
