package io.github.waylandx11.curie

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import libXray.LibXray
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL
import java.security.KeyStore
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * TUN + уведомление + сторож туннеля. Само ядро живёт в этом же процессе:
 * сервис выдаёт дескриптор через `env."xray.tun.fd"`, следит за жизнью сессии
 * и перезапускает ядро, если через локальный прокси пропадет интернет.
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
        private const val PREFS = "curie_vpn_session"
        private const val KEY_CONFIG_ENC = "configEnc"
        private const val KEY_ALIAS = "curie_vpn_session_key"
        private const val KEY_DNS = "dns"
        private const val KEY_MTU = "mtu"
        private const val KEY_MODE = "mode"
        private const val KEY_ALLOWED = "allowed"
        private const val KEY_BYPASSED = "bypassed"
        private const val WATCHDOG_MS = 30_000L
        private const val PROBE_TIMEOUT_MS = 8_000
        private const val PROBE_URL = "http://www.gstatic.com/generate_204"
        private const val RESTART_AFTER_FAILURES = 2

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

    private data class SavedSession(
        val config: String,
        val dns: String,
        val mtu: Int,
        val mode: String,
        val allowed: Set<String>,
        val bypassed: Set<String>
    )

    private val worker = Executors.newSingleThreadExecutor()
    private val watchdog = Handler(Looper.getMainLooper())
    private var watchdogRunnable: Runnable? = null
    private var tun: ParcelFileDescriptor? = null
    private var sessionConfig: String? = null
    private var failures = 0

    // Номер последней команды: задача из очереди не меняет состояние, если
    // пока она ждала, пришла новая команда (например, смена узла).
    private val generation = AtomicInteger(0)

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
                val id = generation.incrementAndGet()
                val session = SavedSession(
                    config = config,
                    dns = intent.getStringExtra(EXTRA_DNS) ?: "77.88.8.8",
                    mtu = intent.getIntExtra(EXTRA_MTU, 1500),
                    mode = intent.getStringExtra(EXTRA_MODE) ?: "all",
                    allowed = (intent.getStringArrayListExtra(EXTRA_ALLOWED) ?: arrayListOf()).toSet(),
                    bypassed = (intent.getStringArrayListExtra(EXTRA_BYPASSED) ?: arrayListOf()).toSet()
                )
                runCatching { saveSession(session) }
                    .onFailure { CurieBridge.log("не удалось сохранить сессию: ${it.message}") }
                startForeground(NOTIFICATION_ID, notification(getString(R.string.vpn_connecting)))
                worker.execute { connectTunnel(session, id) }
                // Сервис должен пережить нехватку памяти: сохранённую сессию
                // можно поднять заново без участия UI.
                return START_STICKY
            }

            ACTION_DISCONNECT -> {
                val id = generation.incrementAndGet()
                clearSavedSession()
                worker.execute { closeTunnel(id, clearSaved = false) }
                return START_NOT_STICKY
            }
        }

        // START_STICKY перезапустил сервис без intent — поднимаем туннель из
        // сохранённого конфига. Если его нет, это был обычный останов.
        val saved = readSavedSession()
        if (saved == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        val id = generation.incrementAndGet()
        startForeground(NOTIFICATION_ID, notification(getString(R.string.vpn_connecting)))
        worker.execute { connectTunnel(saved, id) }
        return START_STICKY
    }

    private fun connectTunnel(session: SavedSession, id: Int) {
        if (id != generation.get()) return
        CurieBridge.emit(CurieBridge.STATUS_CONNECTING)
        try {
            // Переподключение (смена узла или настроек): старую сессию гасим,
            // иначе ядро откажется стартовать поверх работающего экземпляра.
            teardown()
            if (id != generation.get()) return

            val builder = Builder()
                .setSession("Curie")
                .setMtu(session.mtu)
                .addAddress("172.19.0.1", 30)
                .addAddress("fdfe:dcba:9876::1", 126)
                .addDnsServer(session.dns)
                .addRoute("0.0.0.0", 0)
                .addRoute("::", 0)

            applyAppRouting(builder, session.mode, session.allowed.toList(), session.bypassed.toList())

            val fd = builder.establish()
            if (fd == null) {
                CurieBridge.log("establish() вернул null — VPN не разрешён или занят другим приложением")
                throw IllegalStateException("VpnService.establish() вернул null")
            }
            tun?.close()
            tun = fd
            if (id != generation.get()) {
                // Пока ждали establish, пользователь уже выбрал другой узел.
                runCatching { fd.close() }
                tun = null
                return
            }
            sessionConfig = session.config
            CurieBridge.log(
                "tun поднят: fd=${fd.fd}, mtu=${session.mtu}, dns=${session.dns}, режим=${session.mode}"
            )

            val controller = XrayBridge.controllerFor(this)
            // Go-резолвер ядра: запросы уходят мимо туннеля, иначе сервер по имени
            // не найти. Это оптимизация, а не условие запуска: сбой не роняет сессию.
            runCatching { LibXray.setDNS(controller, "${session.dns}:53") }
                .onFailure { CurieBridge.log("setDNS не удался: ${it.javaClass.simpleName}: ${it.message}") }

            if (!startCore(session.config, fd)) return
            if (id != generation.get()) return

            val (metrics, check) = parsePorts(session.config)
            CurieBridge.setSession(metrics, check)
            startWatchdog(check, id)

            updateNotification(getString(R.string.vpn_connected))
            CurieBridge.log("ядро запущено")
            CurieBridge.emit(CurieBridge.STATUS_CONNECTED)
        } catch (t: Throwable) {
            val details = "${t.javaClass.name}: ${t.message ?: "(без сообщения)"}"
            CurieBridge.log("сбой подключения: $details")
            failTunnel(id, details)
        }
    }

    private fun startCore(config: String, fd: ParcelFileDescriptor): Boolean {
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
        return true
    }

    /** Сторож не трогает TUN: только перезапускает ядро внутри живой сессии. */
    private fun startWatchdog(checkPort: Int, id: Int) {
        stopWatchdog()
        if (checkPort <= 0) return
        val task = object : Runnable {
            override fun run() {
                if (id != generation.get() ||
                    CurieBridge.status != CurieBridge.STATUS_CONNECTED ||
                    tun == null
                ) {
                    stopWatchdog()
                    return
                }
                worker.execute { probeTunnel(checkPort, id) }
                watchdog.postDelayed(this, WATCHDOG_MS)
            }
        }
        watchdogRunnable = task
        watchdog.postDelayed(task, WATCHDOG_MS)
    }

    private fun stopWatchdog() {
        watchdogRunnable?.let { watchdog.removeCallbacks(it) }
        watchdogRunnable = null
    }

    private fun probeTunnel(port: Int, id: Int) {
        if (id != generation.get()) return
        if (!hasUnderlyingNetwork()) {
            // Нет сети телефона — это не поломка туннеля; ждём восстановления.
            failures = 0
            return
        }
        val ok = runCatching {
            val connection = URL(PROBE_URL).openConnection(
                Proxy(Proxy.Type.HTTP, InetSocketAddress("127.0.0.1", port))
            ) as HttpURLConnection
            try {
                connection.connectTimeout = PROBE_TIMEOUT_MS
                connection.readTimeout = PROBE_TIMEOUT_MS
                connection.requestMethod = "GET"
                connection.instanceFollowRedirects = false
                connection.responseCode in 200..399
            } finally {
                connection.disconnect()
            }
        }.getOrDefault(false)

        if (ok) {
            failures = 0
            return
        }
        failures++
        if (failures < RESTART_AFTER_FAILURES) return

        val config = sessionConfig
        val fd = tun
        if (config == null || fd == null) return
        failures = 0
        CurieBridge.log("туннель не отвечает: перезапускаю ядро")
        runCatching { XrayBridge.invoke("stopXray", JSONObject()) }
        val error = runCatching { startCore(config, fd) }.exceptionOrNull()
        if (error != null) {
            CurieBridge.log("перезапуск ядра не удался: ${error.message}")
            failTunnel(id, "перезапуск ядра не удался: ${error.message ?: "без ошибки"}")
        }
    }

    private fun hasUnderlyingNetwork(): Boolean {
        val manager = getSystemService(ConnectivityManager::class.java) ?: return true
        val networks = manager.allNetworks
        if (networks.isEmpty()) return false
        return networks.any { network ->
            val caps = manager.getNetworkCapabilities(network) ?: return@any false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
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

    private fun closeTunnel(id: Int, clearSaved: Boolean = true) {
        if (id != generation.get()) return
        CurieBridge.emit(CurieBridge.STATUS_DISCONNECTING)
        teardown()
        if (clearSaved) clearSavedSession()
        CurieBridge.emit(CurieBridge.STATUS_DISCONNECTED)
        stopForegroundIfNeeded()
        stopSelf()
    }

    // Аварийный выход: TUN и ядро гасим, но в UI уходит `error`, а не
    // «отключено», чтобы было видно, что туннель развалился сам.
    private fun failTunnel(id: Int, reason: String) {
        if (id != generation.get()) return
        stopWatchdog()
        clearSavedSession()
        teardown()
        CurieBridge.emit(CurieBridge.STATUS_ERROR, reason)
        stopForegroundIfNeeded()
        stopSelf()
    }

    private fun stopForegroundIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun teardown() {
        stopWatchdog()
        runCatching { XrayBridge.invoke("stopXray", JSONObject()) }
        runCatching { LibXray.resetDNS() }
        runCatching { tun?.close() }
        tun = null
        sessionConfig = null
        failures = 0
        CurieBridge.clearSession()
    }

    private fun saveSession(session: SavedSession) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_CONFIG_ENC, encryptConfig(session.config))
            .putString(KEY_DNS, session.dns)
            .putInt(KEY_MTU, session.mtu)
            .putString(KEY_MODE, session.mode)
            .putStringSet(KEY_ALLOWED, session.allowed)
            .putStringSet(KEY_BYPASSED, session.bypassed)
            .apply()
    }

    private fun clearSavedSession() {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    private fun readSavedSession(): SavedSession? {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val encrypted = prefs.getString(KEY_CONFIG_ENC, null) ?: return null
        // Ключ может быть утерян после сброса данных Keystore: в этом случае
        // просто не поднимаем старую сессию, а не роняем сервис.
        val config = runCatching { decryptConfig(encrypted) }.getOrNull() ?: return null
        return SavedSession(
            config = config,
            dns = prefs.getString(KEY_DNS, null) ?: "77.88.8.8",
            mtu = prefs.getInt(KEY_MTU, 1500),
            mode = prefs.getString(KEY_MODE, null) ?: "all",
            allowed = prefs.getStringSet(KEY_ALLOWED, emptySet()) ?: emptySet(),
            bypassed = prefs.getStringSet(KEY_BYPASSED, emptySet()) ?: emptySet()
        )
    }

    /**
     * Конфиг содержит адреса и ключи узлов, поэтому в SharedPreferences лежит
     * только шифротекст. Ключ создаётся в Android Keystore и не покидает устройство.
     */
    private fun sessionKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(KEY_ALIAS, null)
        if (existing is SecretKey) return existing
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply { init(spec) }
            .generateKey()
    }

    private fun encryptConfig(config: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, sessionKey())
        val blob = cipher.iv + cipher.doFinal(config.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(blob, Base64.DEFAULT)
    }

    private fun decryptConfig(encoded: String): String? {
        val blob = Base64.decode(encoded, Base64.DEFAULT)
        if (blob.size <= 12) return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            sessionKey(),
            GCMParameterSpec(128, blob.copyOfRange(0, 12))
        )
        return String(cipher.doFinal(blob.copyOfRange(12, blob.size)), Charsets.UTF_8)
    }

    private fun parsePorts(config: String): Pair<Int, Int> {
        val json = JSONObject(config)
        val listen = json.optJSONObject("metrics")?.optString("listen").orEmpty()
        val metrics = listen.substringAfterLast(':').toIntOrNull() ?: 0
        val inbounds: JSONArray = json.optJSONArray("inbounds") ?: JSONArray()
        var check = 0
        for (i in 0 until inbounds.length()) {
            val inbound = inbounds.optJSONObject(i) ?: continue
            if (inbound.optString("tag") == "check") {
                check = inbound.optInt("port", 0)
                break
            }
        }
        return metrics to check
    }

    override fun onRevoke() {
        val id = generation.incrementAndGet()
        clearSavedSession()
        worker.execute { closeTunnel(id, clearSaved = false) }
        super.onRevoke()
    }

    override fun onDestroy() {
        stopWatchdog()
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
