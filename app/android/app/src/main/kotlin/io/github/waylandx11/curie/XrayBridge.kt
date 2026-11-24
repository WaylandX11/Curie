package io.github.waylandx11.curie

import android.net.VpnService
import libXray.DialerController
import libXray.LibXray
import org.json.JSONObject

/**
 * Тонкая обёртка над libXray: всё ядро — в этом же процессе, без fork/exec.
 *
 * API: `LibXray.invoke(JSON)` с `{"apiVersion": 3, "method": ..., "payload": ...}`.
 * Ответ: `{"success": bool, "data": ..., "error": "..."}`.
 */
object XrayBridge {
    private const val API_VERSION = 3

    init {
        // Инициализирует Go-рантайм (System.loadLibrary("gojni") внутри libXray).
        LibXray.touch()
    }

    fun invoke(method: String, payload: JSONObject): JSONObject {
        val request = JSONObject()
            .put("apiVersion", API_VERSION)
            .put("method", method)
            .put("payload", payload)
        return JSONObject(LibXray.invoke(request.toString()))
    }

    /**
     * Контроллер, через который ядро выпускает свои сокеты мимо туннеля.
     * Без него Xray уйдёт в петлю: его соединение к серверу попадёт в тот же TUN.
     */
    fun controllerFor(vpn: VpnService): DialerController {
        val controller = object : DialerController {
            override fun protectFd(fd: Long): Boolean = vpn.protect(fd.toInt())
        }
        LibXray.registerDialerController(controller)
        return controller
    }
}
