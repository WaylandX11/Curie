package io.github.waylandx11.curie

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import libXray.LibXray
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * TUN + уведомление. Само ядро живёт в этом же процессе: сервис только
 * выдаёт дескриптор через `env."xray.tun.fd"` и следит за жизнью сессии.
 */
class CurieVpnService : VpnService() {

    companion object {
        const val ACTION_CONNECT = "io.github.waylandx11.curie.CONNECT"
        const val ACTION_DISCONNECT = "io.github.waylandx11.curie.DISCONNECT"
        const val EXTRA_CONFIG = "config"
        const val EXTRA_DNS = "dns"
        const val EXTRA_MTU = "mtu"
        const val EXTRA_MODE = "mode"
        const val EXTRA_ALLOWED = "allowed"
        const val EXTRA_BYPASSED = "bypassed"

        private const val CHANNEL_ID = "vpn"
        private const val NOTIFICATION_ID = 1

        fun start(context: Context, intent: Intent) {
            val service = Intent(intent).setClass(context, CurieVpnService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
        }

        fun disconnect(context: Context) {
            val intent = Intent(context, CurieVpnService::class.java)
                .setAction(ACTION_DISCONNECT)
            context.startService(intent)
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    private var tun: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (config.isNullOrBlank()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startForeground(NOTIFICATION_ID, notification(getString(R.string.vpn_connecting)))
                worker.execute { connectTunnel(intent, config) }
                return START_NOT_STICKY
            }

            ACTION_DISCONNECT -> {
                worker.execute { closeTunnel() }
                return START_NOT_STICKY
            }
        }
        return START_NOT_STICKY
    }

    private fun connectTunnel(intent: Intent, config: String) {
        CurieBridge.emit(CurieBridge.STATUS_CONNECTING)
        try {
            // Переподключение (смена узла или настроек): старую сессию гасим,
            // иначе ядро откажется стартовать поверх работающего экземпляра.
            if (tun != null) teardown()

            val dns = intent.getStringExtra(EXTRA_DNS) ?: "1.1.1.1"
            val mtu = intent.getIntExtra(EXTRA_MTU, 1500)
            val mode = intent.getStringExtra(EXTRA_MODE) ?: "all"
            val allowed = intent.getStringArrayListExtra(EXTRA_ALLOWED) ?: arrayListOf()
            val bypassed = intent.getStringArrayListExtra(EXTRA_BYPASSED) ?: arrayListOf()

            val builder = Builder()
                .setSession("Curie")
                .setMtu(mtu)
                .addAddress("172.19.0.1", 30)
                .addAddress("fdfe:dcba:9876::1", 126)
                .addDnsServer(dns)
                .addRoute("0.0.0.0", 0)
                .addRoute("::", 0)

            applyAppRouting(builder, mode, allowed, bypassed)

            val fd = builder.establish()
            if (fd == null) {
                CurieBridge.log("establish() вернул null — VPN не разрешён или занят другим приложением")
                throw IllegalStateException("VpnService.establish() вернул null")
            }
            tun?.close()
            tun = fd
            CurieBridge.log("tun поднят: fd=${fd.fd}, mtu=$mtu, dns=$dns, режим=$mode")

            val controller = XrayBridge.controllerFor(this)
            // Go-резолвер ядра: запросы уходят мимо туннеля, иначе сервер по имени
            // не найти. Это оптимизация, а не условие запуска: сбой не роняет сессию.
            runCatching { LibXray.setDNS(controller, "$dns:53") }
                .onFailure { CurieBridge.log("setDNS не удался: ${it.javaClass.simpleName}: ${it.message}") }

            val json = JSONObject(config)
            val env = json.optJSONObject("env") ?: JSONObject()
            env.put("xray.tun.fd", fd.fd.toString())
            json.put("env", env)

            val response = XrayBridge.invoke(
                "runXray",
                JSONObject().put("xrayJson", json.toString())
            )
            if (!response.optBoolean("success", false)) {
                val error = response.optString("error")
                CurieBridge.log("runXray отказал: $error")
                throw IllegalStateException(error.ifBlank { "Ядро не запустилось (пустой ответ)" })
            }

            updateNotification(getString(R.string.vpn_connected))
            CurieBridge.log("ядро запущено")
            CurieBridge.emit(CurieBridge.STATUS_CONNECTED)
        } catch (t: Throwable) {
            val details = "${t.javaClass.name}: ${t.message ?: "(без сообщения)"}"
            CurieBridge.log("сбой подключения: $details")
            teardown()
            CurieBridge.emit(CurieBridge.STATUS_ERROR, details)
            stopSelf()
        }
    }

    /**
     * Раздельное туннелирование. Смешивать allowed и disallowed нельзя —
     * Android бросит исключение, поэтому режимы взаимоисключающие.
     */
    private fun applyAppRouting(
        builder: Builder,
        mode: String,
        allowed: List<String>,
        bypassed: List<String>
    ) {
        if (mode == "only") {
            var added = 0
            for (pkg in allowed) {
                if (pkg == packageName) continue
                runCatching { builder.addAllowedApplication(pkg) }.onSuccess { added++ }
            }
            if (added > 0) {
                // Своё приложение не в списке — оно и так вне туннеля, петли нет.
                return
            }
            // Ни одно приложение не подошло (удалено, скрыто) — не оставляем
            // пользователя без сети: откатываемся к обычному полному туннелю.
        }

        // Свои сокеты не должны попадать в собственный туннель: вторая линия
        // защиты после protectFd в контроллере libXray.
        runCatching { builder.addDisallowedApplication(packageName) }
        if (mode == "bypass") {
            for (pkg in bypassed) {
                if (pkg == packageName) continue
                runCatching { builder.addDisallowedApplication(pkg) }
            }
        }
    }

    private fun closeTunnel() {
        CurieBridge.emit(CurieBridge.STATUS_DISCONNECTING)
        teardown()
        CurieBridge.emit(CurieBridge.STATUS_DISCONNECTED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun teardown() {
        runCatching { XrayBridge.invoke("stopXray", JSONObject()) }
        runCatching { LibXray.resetDNS() }
        runCatching { tun?.close() }
        tun = null
    }

    override fun onRevoke() {
        worker.execute { closeTunnel() }
        super.onRevoke()
    }

    override fun onDestroy() {
        teardown()
        worker.shutdown()
        super.onDestroy()
    }

    // --- уведомление --------------------------------------------------------

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.vpn_channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply { setShowBadge(false) }
        manager.createNotificationChannel(channel)
    }

    private fun notification(text: String): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, CurieVpnService::class.java).setAction(ACTION_DISCONNECT),
            PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_vpn)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    getString(R.string.vpn_disconnect),
                    stop
                ).build()
            )
            .build()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification(text))
    }
}
