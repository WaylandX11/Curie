package io.github.waylandx11.curie

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import org.xrayrust.mobile.XrayTunBackend
import org.xrayrust.mobile.XrayTunRuntimeProfile
import org.xrayrust.mobile.XrayVpnService
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Экспериментальный туннель на xray-rust-mobile. Включается только явным
 * переключателем; по умолчанию работает обычный CurieVpnService + libXray.
 *
 * Native-слой сам держит VpnService и ТUN-дескриптор, поэтому здесь только
 * конфиг, параметры Android-туннеля, уведомление и мост в CurieBridge.
 */
class CurieRustVpnService : XrayVpnService() {

    companion object {
        const val ACTION_CONNECT = "io.github.waylandx11.curie.RUST_CONNECT"
        const val ACTION_DISCONNECT = "io.github.waylandx11.curie.RUST_DISCONNECT"
        const val EXTRA_CONFIG = "config"
        const val EXTRA_GEO_DIR = "geoDir"
        const val EXTRA_DNS = "dns"
        const val EXTRA_MTU = "mtu"
        const val EXTRA_MODE = "mode"
        const val EXTRA_ALLOWED = "allowed"
        const val EXTRA_BYPASSED = "bypassed"

        /** Версия мобильной обёртки AAR; показываем её, а не внутренний FFI. */
        private const val AAR_VERSION = "0.10.1"

        private const val CHANNEL_ID = "vpn"
        private const val NOTIFICATION_ID = 1
        private const val PREFS = "curie_rust_vpn_session"
        private const val KEY_CONFIG_ENC = "configEnc"
        private const val KEY_ALIAS = "curie_rust_vpn_session_key"
        private const val KEY_DNS = "dns"
        private const val KEY_MTU = "mtu"
        private const val KEY_MODE = "mode"
        private const val KEY_ALLOWED = "allowed"
        private const val KEY_BYPASSED = "bypassed"
        private const val KEY_GEO_DIR = "geoDir"

        @Volatile
        private var active: CurieRustVpnService? = null

        /** Счётчики активного Rust-туннеля, или null если его нет. */
        fun currentTraffic(): Map<String, Long>? = active?.trafficTotals()

        fun start(context: Context, intent: Intent) {
            val service = Intent(intent).setClass(context, CurieRustVpnService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
        }

        fun disconnect(context: Context) {
            val intent = Intent(context, CurieRustVpnService::class.java)
                .setAction(ACTION_DISCONNECT)
            runCatching { context.startService(intent) }
        }

        /** Версия Rust-ядра для UI, User-Agent и журнала. */
        fun version(): String = AAR_VERSION

        /**
         * Убираем только то, что относится к Go-ядру и его локальным сервисам.
         * Селекторы, стратегии и `fallbackTag` остаются панельными — Rust
         * 0.10.1 понимает их нативно, поэтому правила с `balancerTag` здесь
         * трогать нельзя. Dart лишь заменяет неподдерживаемый
         * `burstObservatory` на обычный `observatory`.
         */
        fun sanitizeConfig(raw: String): String {
            val json = JSONObject(raw)
            json.remove("metrics")
            json.remove("stats")
            json.remove("policy")
            json.remove("env")

            // Rust-ядро принимает не все поля панели: эти два она отвергает
            // как неизвестные ещё до запуска. Убираем их везде, включая
            // вложенные объекты.
            // `domainMatcher` Rust отвергает как неизвестное ещё до запуска.
            stripKeys(json, setOf("domainMatcher"))

            val inbounds = json.optJSONArray("inbounds") ?: JSONArray()
            val kept = JSONArray()
            for (i in 0 until inbounds.length()) {
                val inbound = inbounds.optJSONObject(i) ?: continue
                // check-прокси оставляем: через него Dart делает «Проверить»
                // и фоновые запросы, пока туннель активен.
                if (inbound.optString("tag") == "tun") {
                    // AAR задаёт MTU через xray_core_set_tun_mtu вместе с интерфейсом.
                    inbound.optJSONObject("settings")?.apply {
                        remove("name")
                        remove("mtu")
                    }
                    inbound.optJSONObject("sniffing")?.remove("routeOnly")
                }
                kept.put(inbound)
            }
            json.put("inbounds", kept)

            return json.toString()
        }

        /** Порт локального check-прокси из конфига, 0 если его нет. */
        fun checkPort(raw: String): Int = runCatching {
            val inbounds = JSONObject(raw).optJSONArray("inbounds") ?: return 0
            for (i in 0 until inbounds.length()) {
                val inbound = inbounds.optJSONObject(i) ?: continue
                if (inbound.optString("tag") == "check") {
                    return inbound.optInt("port", 0)
                }
            }
            0
        }.getOrDefault(0)

        /** Рекурсивно вырезает поля, которых нет в схеме Rust-ядра. */
        private fun stripKeys(json: JSONObject, keys: Set<String>) {
            val iterator = json.keys()
            while (iterator.hasNext()) {
                val key = iterator.next()
                if (key in keys) {
                    iterator.remove()
                    continue
                }
                val value = json.opt(key)
                when (value) {
                    is JSONObject -> stripKeys(value, keys)
                    is JSONArray -> stripKeys(value, keys)
                }
            }
        }

        private fun stripKeys(array: JSONArray, keys: Set<String>) {
            for (i in 0 until array.length()) {
                when (val value = array.opt(i)) {
                    is JSONObject -> stripKeys(value, keys)
                    is JSONArray -> stripKeys(value, keys)
                }
            }
        }
    }

    private data class SavedSession(
        val config: String,
        val dns: String,
        val mtu: Int,
        val mode: String,
        val allowed: Set<String>,
        val bypassed: Set<String>,
        val geoDir: String
    )

    private var currentDns = "8.8.8.8"
    private var currentMtu = 1500
    private var currentMode = "all"
    private var currentAllowed = emptyList<String>()
    private var currentBypassed = emptyList<String>()
    private var currentGeoDir = ""
    private var currentCheckPort = 0

    /**
     * AAR возвращает `onXrayTunnelStartCancelled` для старой сессии, когда
     * новая заменяет работающий туннель. В этот момент останавливать сервис
     * нельзя: заменяемый запуск ещё только стартует.
     */
    @Volatile
    private var startPending = false
    private var wakeLock: PowerManager.WakeLock? = null

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Curie:RustVpn").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        runCatching { wakeLock?.release() }
        wakeLock = null
    }

    override fun onCreate() {
        super.onCreate()
        active = this
        CurieBridge.setCore("rust")
        createChannel()
    }

    /** Накопительные байты ядра; скорость Dart считает как дельту за секунду. */
    fun trafficTotals(): Map<String, Long> = runCatching {
        val stats = xrayVpnRuntimeSnapshot().tunStats
            ?: return mapOf("up" to 0L, "down" to 0L)
        mapOf("up" to stats.uplinkBytes, "down" to stats.downlinkBytes)
    }.getOrDefault(mapOf("up" to 0L, "down" to 0L))

    override fun onDestroy() {
        releaseWakeLock()
        if (active === this) active = null
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val raw = intent.getStringExtra(EXTRA_CONFIG)
                if (raw.isNullOrBlank()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                val session = SavedSession(
                    config = raw,
                    dns = intent.getStringExtra(EXTRA_DNS) ?: "8.8.8.8",
                    mtu = intent.getIntExtra(EXTRA_MTU, 1500),
                    mode = intent.getStringExtra(EXTRA_MODE) ?: "all",
                    allowed = (intent.getStringArrayListExtra(EXTRA_ALLOWED) ?: arrayListOf()).toSet(),
                    bypassed = (intent.getStringArrayListExtra(EXTRA_BYPASSED) ?: arrayListOf()).toSet(),
                    geoDir = intent.getStringExtra(EXTRA_GEO_DIR) ?: "",
                )
                runCatching { saveSession(session) }
                    .onFailure { CurieBridge.log("Rust: не удалось сохранить сессию: ${it.message}") }
                startForeground(NOTIFICATION_ID, notification(getString(R.string.vpn_connecting)))
                connect(session)
                return START_STICKY
            }

            ACTION_DISCONNECT -> {
                startPending = false
                clearSavedSession()
                CurieBridge.emit(CurieBridge.STATUS_DISCONNECTING)
                runCatching { stopXrayTunnel() }
                CurieBridge.clearSession()
                CurieBridge.emit(CurieBridge.STATUS_DISCONNECTED)
                stopForegroundIfNeeded()
                releaseWakeLock()
                stopSelf()
                return START_NOT_STICKY
            }
        }

        val saved = readSavedSession()
        if (saved == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTIFICATION_ID, notification(getString(R.string.vpn_connecting)))
        connect(saved)
        return START_STICKY
    }

    private fun connect(session: SavedSession) {
        acquireWakeLock()
        currentDns = session.dns
        currentMtu = session.mtu
        currentMode = session.mode
        currentAllowed = session.allowed.toList()
        currentBypassed = session.bypassed.toList()
        currentGeoDir = session.geoDir
        currentCheckPort = checkPort(session.config)
        CurieBridge.emit(CurieBridge.STATUS_CONNECTING)
        CurieBridge.log("Запуск xray-rust ${version()}")

        // AAR начинает замену только после явной остановки предыдущего
        // туннеля: beginOrReplaceStart сам его не снимает. Без этого новый
        // конфиг остаётся в очереди и ни один колбэк не приходит.
        val running = runCatching { xrayVpnRuntimeSnapshot().running }.getOrDefault(false)
        if (running) {
            CurieBridge.log("Rust: смена узла, останавливаем предыдущий туннель")
            startPending = false
            runCatching { stopXrayTunnel() }
                .onFailure { CurieBridge.log("Rust: ошибка остановки: ${it.message}") }
        }

        startPending = true
        runCatching {
            startXrayTunnel(
                sanitizeConfig(session.config),
                XrayTunBackend.FileDescriptor,
                XrayTunRuntimeProfile.Default,
                null, // AAR допускает отключение стартового probe; проверку делает Dart-сторож.
                session.mtu,
            )
        }.onFailure {
            val reason = "${it.javaClass.simpleName}: ${it.message ?: "без сообщения"}"
            CurieBridge.log("Rust: сбой запуска: $reason")
            CurieBridge.emit(CurieBridge.STATUS_ERROR, reason)
            stopForegroundIfNeeded()
            stopSelf()
        }
    }

    /** Параметры Android-интерфейса: AAR вызывает этот метод перед establish(). */
    override fun buildTunnel(): VpnService.Builder {
        val builder = Builder()
            .setSession("Curie (Rust)")
            .setMtu(currentMtu)
            .addAddress("172.19.0.1", 30)
            .addAddress("fdfe:dcba:9876::1", 126)
            .addDnsServer(currentDns)
            .addRoute("0.0.0.0", 0)
            .addRoute("::", 0)

        if (currentMode == "only") {
            var added = 0
            for (pkg in currentAllowed) {
                if (pkg == packageName) continue
                try {
                    builder.addAllowedApplication(pkg)
                    added++
                } catch (_: Exception) {
                    // Пакет мог быть удалён — пропускаем его.
                }
            }
            if (added == 0) {
                // Ни одно приложение не подошло — лучше оставить сеть работающей.
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (_: Exception) {
                }
            }
            return builder
        }

        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: Exception) {
        }
        if (currentMode == "bypass") {
            for (pkg in currentBypassed) {
                if (pkg == packageName) continue
                try {
                    builder.addDisallowedApplication(pkg)
                } catch (_: Exception) {
                }
            }
        }
        return builder
    }

    override fun geodataSearchDirectory(): File? =
        currentGeoDir.takeIf { it.isNotEmpty() }?.let(::File)

    override fun onXrayTunnelStarted() {
        startPending = false
        // Метрик Go здесь нет: скорость идёт из tunStats. Локальный check-прокси
        // оставляем working, чтобы кнопка «Проверить» и фоновые запросы шли
        // через туннель так же, как в обычном режиме.
        CurieBridge.setSession(0, currentCheckPort)
        updateNotification(getString(R.string.vpn_connected))
        CurieBridge.log("xray-rust ${version()} запущено")
        CurieBridge.emit(CurieBridge.STATUS_CONNECTED)
    }

    override fun onXrayTunnelStartFailed(error: Throwable) {
        startPending = false
        val reason = "${error.javaClass.simpleName}: ${error.message ?: "без сообщения"}"
        CurieBridge.log("Rust: запуск не удался: $reason")
        CurieBridge.clearSession()
        CurieBridge.emit(CurieBridge.STATUS_ERROR, reason)
        stopForegroundIfNeeded()
        stopSelf()
    }

    override fun onXrayTunnelStartCancelled() {
        // Колбэк относится к ПРЕДЫДУЩЕЙ сессии, которую мы только что сняли
        // перед запуском нового конфига. Закрывать сервис здесь — значит
        // оборвать заменяемый запуск и оставить кнопку «Подключение…» навсегда.
        if (startPending || runCatching { xrayVpnRuntimeSnapshot().running }.getOrDefault(false)) {
            CurieBridge.log("Rust: предыдущий запуск отменён, ждём новый")
            return
        }
        CurieBridge.clearSession()
        CurieBridge.emit(CurieBridge.STATUS_DISCONNECTED)
        stopForegroundIfNeeded()
        stopSelf()
    }

    override fun onXrayTunnelFatalError(error: Throwable) {
        startPending = false
        val reason = "${error.javaClass.simpleName}: ${error.message ?: "без сообщения"}"
        CurieBridge.log("Rust: ошибка ядра: $reason")
        clearSavedSession()
        CurieBridge.clearSession()
        CurieBridge.emit(CurieBridge.STATUS_ERROR, reason)
        stopForegroundIfNeeded()
        stopSelf()
    }

    override fun onXrayNetworkRebind(result: org.xrayrust.mobile.XrayNetworkRebindResult) {
        CurieBridge.log("Rust: смена сети обработана")
    }

    override fun onXrayNetworkChangeError(error: Exception) {
        CurieBridge.log("Rust: смена сети: ${error.message ?: error.javaClass.simpleName}")
    }

    override fun onRevoke() {
        startPending = false
        clearSavedSession()
        CurieBridge.clearSession()
        CurieBridge.emit(CurieBridge.STATUS_DISCONNECTED)
        stopForegroundIfNeeded()
        stopSelf()
        super.onRevoke()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Curie VPN",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    private fun notification(text: String): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Curie")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_vpn)
            .setContentIntent(pending)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String) {
        runCatching {
            getSystemService(NotificationManager::class.java)
                ?.notify(NOTIFICATION_ID, notification(text))
        }
    }

    private fun stopForegroundIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun sessionKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(KEY_ALIAS, null)
        if (existing is SecretKey) return existing
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
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
            GCMParameterSpec(128, blob.copyOfRange(0, 12)),
        )
        return String(cipher.doFinal(blob.copyOfRange(12, blob.size)), Charsets.UTF_8)
    }

    private fun saveSession(session: SavedSession) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_CONFIG_ENC, encryptConfig(session.config))
            .putString(KEY_DNS, session.dns)
            .putInt(KEY_MTU, session.mtu)
            .putString(KEY_MODE, session.mode)
            .putStringSet(KEY_ALLOWED, session.allowed)
            .putStringSet(KEY_BYPASSED, session.bypassed)
            .putString(KEY_GEO_DIR, session.geoDir)
            .apply()
    }

    private fun clearSavedSession() {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    private fun readSavedSession(): SavedSession? {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val encrypted = prefs.getString(KEY_CONFIG_ENC, null) ?: return null
        val config = runCatching { decryptConfig(encrypted) }.getOrNull() ?: return null
        return SavedSession(
            config = config,
            dns = prefs.getString(KEY_DNS, null) ?: "8.8.8.8",
            mtu = prefs.getInt(KEY_MTU, 1500),
            mode = prefs.getString(KEY_MODE, null) ?: "all",
            allowed = prefs.getStringSet(KEY_ALLOWED, emptySet()) ?: emptySet(),
            bypassed = prefs.getStringSet(KEY_BYPASSED, emptySet()) ?: emptySet(),
            geoDir = prefs.getString(KEY_GEO_DIR, null) ?: "",
        )
    }
}
