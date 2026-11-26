package io.github.waylandx11.curie

import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel

/**
 * Состояние туннеля, общее для сервиса и Flutter-слоя.
 *
 * Сервис живёт дольше Activity, поэтому статус и параметры сессии хранятся
 * здесь, а не в канале: после перезапуска UI достаточно спросить `status`.
 */
object CurieBridge {
    const val STATUS_DISCONNECTED = "disconnected"
    const val STATUS_CONNECTING = "connecting"
    const val STATUS_CONNECTED = "connected"
    const val STATUS_DISCONNECTING = "disconnecting"
    const val STATUS_ERROR = "error"

    @Volatile
    private var channel: MethodChannel? = null

    @Volatile
    var status: String = STATUS_DISCONNECTED
        private set

    @Volatile
    var lastError: String? = null
        private set

    @Volatile
    private var metricsPort: Int = 0

    @Volatile
    private var checkPort: Int = 0

    // Какое ядро держит активный туннель. Dart использует это, чтобы выбрать
    // источник версии и счётчиков трафика после пересоздания движка.
    @Volatile
    private var coreName: String = "xray"

    @Volatile
    private var connectedAtMs: Long = 0

    private val main = Handler(Looper.getMainLooper())

    // Меняется только при реальной смерти процесса. Пересоздание Flutter-движка
    // внутри живого процесса оставляет токен прежним — по этому признаку Dart
    // отличает «запуск Curie» от простого возврата в интерфейс.
    private val processStartRealtimeMs = SystemClock.elapsedRealtime()

    fun processToken(): String = "${Process.myPid()}-$processStartRealtimeMs"

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    fun setCore(name: String) {
        coreName = name
    }

    fun setSession(metricsPort: Int, checkPort: Int) {
        this.metricsPort = metricsPort
        this.checkPort = checkPort
        this.connectedAtMs = System.currentTimeMillis()
    }

    fun clearSession() {
        metricsPort = 0
        checkPort = 0
        connectedAtMs = 0
    }

    fun session(): Map<String, Any?> = mapOf(
        "metrics" to metricsPort,
        "check" to checkPort,
        "connectedAt" to connectedAtMs,
        "core" to coreName
    )

    fun emit(status: String, error: String? = null) {
        this.status = status
        this.lastError = error
        val payload = HashMap<String, Any?>().apply {
            put("status", status)
            put("error", error)
            putAll(session())
        }
        main.post { channel?.invokeMethod("stateChanged", payload) }
    }

    /** Строка в журнал Dart-слоя: видно, на каком шаге всё сломалось. */
    fun log(message: String) {
        main.post { channel?.invokeMethod("log", mapOf("message" to message)) }
    }
}
