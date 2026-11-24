package io.github.waylandx11.curie

import android.app.Service
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import libXray.LibXray
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * Замер через узел в отдельном процессе.
 *
 * libXray запрещает `pingBatch`, пока в процессе работает основной экземпляр
 * ядра (`runXray`). Отдельный процесс `:ping` даёт второй, чистый libXray —
 * поэтому пинг через прокси работает и при поднятом туннеле, без переключения
 * на TCP и без остановки VPN.
 */
class PingService : Service() {

    companion object {
        const val MSG_INVOKE = 1
        const val MSG_RESULT = 2
        const val ARG_REQUEST = "request"
        const val ARG_ID = "id"
        const val ARG_RESULT = "result"
    }

    private val worker = Executors.newSingleThreadExecutor()
    private var touched = false

    private val handler = Handler(Looper.getMainLooper()) { message ->
        when (message.what) {
            MSG_INVOKE -> {
                val request = message.data?.getString(ARG_REQUEST)
                val id = message.data?.getInt(ARG_ID) ?: 0
                val reply = message.replyTo
                if (request == null || reply == null) return@Handler true

                worker.execute {
                    val payload = runCatching {
                        if (!touched) {
                            LibXray.touch()
                            touched = true
                        }
                        LibXray.invoke(request)
                    }.getOrElse { error ->
                        JSONObject()
                            .put("success", false)
                            .put("error", error.message ?: error.javaClass.simpleName)
                            .toString()
                    }

                    val response = Message.obtain(null, MSG_RESULT)
                    response.data = Bundle().apply {
                        putInt(ARG_ID, id)
                        putString(ARG_RESULT, payload)
                    }
                    runCatching { reply.send(response) }
                }
                true
            }

            else -> false
        }
    }

    private val messenger = Messenger(handler)

    override fun onBind(intent: Intent?): IBinder = messenger.binder

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }
}
