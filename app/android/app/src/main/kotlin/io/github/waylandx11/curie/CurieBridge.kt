package io.github.waylandx11.curie

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Состояние туннеля, общее для сервиса и Flutter-слоя.
 *
 * Сервис живёт дольше Activity, поэтому статус хранится здесь, а не в канале:
 * после перезапуска UI достаточно спросить `status`, чтобы узнать правду.
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

    private val main = Handler(Looper.getMainLooper())

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    fun emit(status: String, error: String? = null) {
        this.status = status
        this.lastError = error
        val payload = mapOf("status" to status, "error" to error)
        main.post { channel?.invokeMethod("stateChanged", payload) }
    }

    /** Строка в журнал Dart-слоя: видно, на каком шаге всё сломалось. */
    fun log(message: String) {
        main.post { channel?.invokeMethod("log", mapOf("message" to message)) }
    }
}
