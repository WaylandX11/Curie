package io.github.waylandx11.curie

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.RemoteException
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "io.github.waylandx11.curie/bridge"
        const val VPN_REQUEST = 0x5643
        const val NOTIFICATION_REQUEST = 0x4E4F
        const val ICON_SIZE = 64
    }

    private val worker = Executors.newSingleThreadExecutor()
    private var pendingConnect: Intent? = null
    private var pendingResult: MethodChannel.Result? = null

    // Замер через узел при поднятом туннеле уходит в отдельный процесс `:ping`:
    // libXray не разрешает pingBatch рядом с работающим runXray.
    private var pingService: Messenger? = null
    private var pingBound = false
    private var nextPingId = 1
    private val pingWaiters = mutableListOf<(Messenger?) -> Unit>()
    private val pendingPings = mutableMapOf<Int, MethodChannel.Result>()

    private val pingReplies = Messenger(object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(message: Message) {
            if (message.what != PingService.MSG_RESULT) return
            val data = message.data ?: return
            val id = data.getInt(PingService.ARG_ID)
            val raw = data.getString(PingService.ARG_RESULT)
            val pending = pendingPings.remove(id) ?: return
            if (raw != null) {
                pending.success(raw)
            } else {
                pending.error("xray", "пустой ответ процесса замера", null)
            }
        }
    })

    private val pingConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            pingService = service?.let { Messenger(it) }
            pingBound = true
            flushPingWaiters()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            // Binding остаётся активным: система поднимет процесс снова.
            pingService = null
            failPendingPings("процесс замера остановлен")
        }

        override fun onBindingDied(name: ComponentName?) {
            pingService = null
            pingBound = false
            failPendingPings("процесс замера перезапущен")
        }

        override fun onNullBinding(name: ComponentName?) {
            pingBound = false
            flushPingWaiters()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        CurieBridge.attach(channel)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "invoke" -> {
                    val request = call.argument<String>("request")
                    if (request == null) {
                        result.error("bad_request", "request is null", null)
                        return@setMethodCallHandler
                    }
                    if (pingNeedsIsolatedProcess(request)) {
                        invokeInPingProcess(request, result)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        try {
                            val raw = libXray.LibXray.invoke(request)
                            runOnUiThread { result.success(raw) }
                        } catch (t: Throwable) {
                            runOnUiThread { result.error("xray", t.message, null) }
                        }
                    }
                }

                "connect" -> startTunnel(connectIntent(call.arguments()), result)

                "disconnect" -> {
                    // Останавливаем оба сервиса: пользователь мог выключить
                    // экспериментальный переключатель во время работы туннеля.
                    CurieVpnService.disconnect(this)
                    CurieRustVpnService.disconnect(this)
                    result.success(null)
                }

                // Версия Rust-ядра. Go-версию Dart запрашивает через `invoke`.
                "rustCoreVersion" -> result.success(CurieRustVpnService.version())

                // Накопительные счётчики Rust-ядра. Показываются вместо
                // HTTP-метрик libXray, когда включён experimental-режим.
                "rustTraffic" -> result.success(CurieRustVpnService.currentTraffic())

                "status" -> result.success(
                    HashMap<String, Any?>().apply {
                        put("status", CurieBridge.status)
                        put("error", CurieBridge.lastError)
                        putAll(CurieBridge.session())
                    }
                )

                // Токен процесса: нужен, чтобы журнал не писал «запуск Curie»
                // при каждом пересоздании Flutter-движка.
                "processToken" -> result.success(CurieBridge.processToken())

                // Geo-базы обновляем только по безлимитной сети, если включён
                // переключатель «Только по Wi-Fi». Собственный VPN не учитываем.
                "isUnmeteredNetwork" -> result.success(isUnmeteredNetwork())

                // ANDROID_ID: стабилен для пары «устройство + подпись приложения»,
                // живёт после переустановки. В Dart из него выводится HWID через HMAC,
                // само значение наружу не уходит.
                "androidId" -> result.success(
                    runCatching {
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    }.getOrNull()
                )

                // Версия ОС для User-Agent: Build.VERSION.RELEASE даёт «17»,
                // а не внутренний SDK. ANDROID_ID и прочая идентификация тут не нужны.
                "platformInfo" -> result.success(
                    mapOf(
                        "os" to "Android",
                        "version" to Build.VERSION.RELEASE,
                        "sdk" to Build.VERSION.SDK_INT
                    )
                )

                "listApps" -> worker.execute {
                    try {
                        val apps = installedApps()
                        runOnUiThread { result.success(apps) }
                    } catch (t: Throwable) {
                        runOnUiThread { result.error("apps", t.message, null) }
                    }
                }

                // Иконка запрашивается только для видимых строк списка.
                "appIcon" -> {
                    val pkg = call.argument<String>("package")
                    if (pkg.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    worker.execute {
                        val icon = appIcon(pkg)
                        runOnUiThread { result.success(icon) }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun pingNeedsIsolatedProcess(request: String): Boolean {
        if (CurieBridge.status != CurieBridge.STATUS_CONNECTED &&
            CurieBridge.status != CurieBridge.STATUS_CONNECTING
        ) {
            return false
        }
        return runCatching {
            JSONObject(request).optString("method") == "pingBatch"
        }.getOrDefault(false)
    }

    private fun invokeInPingProcess(request: String, result: MethodChannel.Result) {
        bindPingService { messenger ->
            if (messenger == null) {
                result.error("xray", "не удалось запустить изолированный процесс замера", null)
                return@bindPingService
            }

            val id = nextPingId++
            pendingPings[id] = result
            val message = Message.obtain(null, PingService.MSG_INVOKE)
            message.replyTo = pingReplies
            message.data = Bundle().apply {
                putString(PingService.ARG_REQUEST, request)
                putInt(PingService.ARG_ID, id)
            }
            try {
                messenger.send(message)
            } catch (e: RemoteException) {
                pendingPings.remove(id)
                result.error("xray", e.message, null)
            }
        }
    }

    private fun bindPingService(onReady: (Messenger?) -> Unit) {
        pingService?.let {
            onReady(it)
            return
        }

        pingWaiters.add(onReady)
        if (pingBound) return

        pingBound = true
        val intent = Intent(this, PingService::class.java)
        val started = runCatching {
            bindService(intent, pingConnection, Context.BIND_AUTO_CREATE)
        }.getOrDefault(false)

        if (!started) {
            pingBound = false
            flushPingWaiters()
        }
    }

    private fun flushPingWaiters() {
        val waiters = pingWaiters.toList()
        pingWaiters.clear()
        for (waiter in waiters) waiter(pingService)
    }

    private fun failPendingPings(reason: String) {
        val pending = pendingPings.values.toList()
        pendingPings.clear()
        for (result in pending) result.error("xray", reason, null)
    }

    private fun connectIntent(arguments: Any?): Intent? {
        @Suppress("UNCHECKED_CAST")
        val args = arguments as? Map<String, Any?> ?: return null
        val config = args["config"] as? String ?: return null
        val tunnelMode = args["tunnelMode"] as? String ?: "tun"
        val useRust = args["useRustCore"] == true
        // AAR управляет TUN сам и не умеет работать без VpnService: режим
        // «Proxy» остаётся на проверенном libXray-пути.
        val rust = useRust && tunnelMode != "proxy"
        val service = if (rust) CurieRustVpnService::class.java else CurieVpnService::class.java
        val configExtra = if (rust) {
            CurieRustVpnService.EXTRA_CONFIG
        } else {
            CurieVpnService.EXTRA_CONFIG
        }

        return Intent(this, service).apply {
            action = if (rust) {
                CurieRustVpnService.ACTION_CONNECT
            } else {
                CurieVpnService.ACTION_CONNECT
            }
            putExtra(configExtra, config)
            putExtra(CurieVpnService.EXTRA_TUNNEL_MODE, tunnelMode)
            putExtra(CurieVpnService.EXTRA_USE_RUST_CORE, rust)
            putExtra(
                CurieVpnService.EXTRA_GEO_DIR,
                args["geoDir"] as? String ?: "",
            )
            putExtra(CurieVpnService.EXTRA_DNS, (args["dns"] as? String) ?: "77.88.8.8")
            putExtra(CurieVpnService.EXTRA_MTU, (args["mtu"] as? Int) ?: 1500)
            putExtra(CurieVpnService.EXTRA_MODE, (args["mode"] as? String) ?: "all")
            putExtra(
                CurieVpnService.EXTRA_ALLOWED,
                ArrayList((args["allowed"] as? List<*>)?.filterIsInstance<String>() ?: emptyList())
            )
            putExtra(
                CurieVpnService.EXTRA_BYPASSED,
                ArrayList((args["bypassed"] as? List<*>)?.filterIsInstance<String>() ?: emptyList())
            )
        }
    }

    private fun startTunnel(intent: Intent?, result: MethodChannel.Result) {
        if (intent == null) {
            result.error("bad_request", "config is null", null)
            return
        }
        // Android 13+: без POST_NOTIFICATIONS уведомление VPN не появится в
        // шторке, а значит не будет и значка. Спрашиваем до prepare(), иначе
        // два диалога наложатся друг на друга.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingConnect = intent
            pendingResult = result
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_REQUEST
            )
            return
        }
        // SOCKS5 без TUN не требует разрешения VpnService.
        if (intent.getStringExtra(CurieVpnService.EXTRA_TUNNEL_MODE) == "proxy") {
            startTunnelService(intent)
            result.success(null)
            return
        }
        prepareVpn(intent, result)
    }

    private fun prepareVpn(intent: Intent, result: MethodChannel.Result) {
        val prepare = VpnService.prepare(this)
        if (prepare != null) {
            pendingConnect = intent
            pendingResult = result
            startActivityForResult(prepare, VPN_REQUEST)
            return
        }
        startTunnelService(intent)
        result.success(null)
    }

    /** Один путь запуска и до, и после диалога разрешения VPN. */
    private fun startTunnelService(intent: Intent) {
        if (intent.getBooleanExtra(CurieVpnService.EXTRA_USE_RUST_CORE, false)) {
            CurieRustVpnService.start(this, intent)
        } else {
            CurieVpnService.start(this, intent)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == NOTIFICATION_REQUEST) {
            val intent = pendingConnect
            val result = pendingResult
            pendingConnect = null
            pendingResult = null
            // Даже при отказе запускаем туннель: VPN важнее уведомления.
            if (intent != null && result != null) prepareVpn(intent, result)
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VPN_REQUEST) {
            val intent = pendingConnect
            val result = pendingResult
            pendingConnect = null
            pendingResult = null
            if (resultCode == Activity.RESULT_OK && intent != null) {
                startTunnelService(intent)
                result?.success(null)
            } else {
                result?.error("vpn_denied", "VPN permission denied", null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** Есть ли безлимитная сеть мимо собственного VPN. */
    private fun isUnmeteredNetwork(): Boolean {
        val manager = getSystemService(ConnectivityManager::class.java) ?: return false
        return manager.allNetworks.any { network ->
            val caps = manager.getNetworkCapabilities(network) ?: return@any false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI))
        }
    }

    /**
     * Все установленные приложения — включая системные и те, у которых нет
     * иконки в лаунчере (Android Auto, GMS, сервисы). Для раздельного
     * туннелирования нужен полный список, поэтому объявлен QUERY_ALL_PACKAGES;
     * в Play он требует декларации. Иконки здесь не грузим: список стал
     * большим, их выдаёт отдельный `appIcon` по требованию.
     */
    private fun installedApps(): List<Map<String, Any>> {
        val pm = packageManager
        val infos = runCatching { pm.getInstalledApplications(0) }.getOrElse { emptyList() }
        val apps = ArrayList<Map<String, Any>>(infos.size)

        for (info in infos) {
            val pkg = info.packageName
            if (pkg == packageName) continue
            if ((info.flags and ApplicationInfo.FLAG_INSTALLED) == 0) continue

            val label = runCatching { pm.getApplicationLabel(info).toString() }
                .getOrNull()
                ?.takeIf { it.isNotBlank() }
                ?: continue

            val system = (info.flags and (
                ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP
                )) != 0

            apps.add(
                mapOf(
                    "package" to pkg,
                    "label" to label,
                    "system" to system
                )
            )
        }
        return apps
    }

    /** Иконка одного приложения: PNG 64×64 или null, если её нет. */
    private fun appIcon(pkg: String): ByteArray? = runCatching {
        val info = packageManager.getApplicationInfo(pkg, 0)
        iconBytes(packageManager.getApplicationIcon(info))
    }.getOrNull()

    private fun iconBytes(drawable: Drawable): ByteArray {
        val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, ICON_SIZE, ICON_SIZE)
        drawable.draw(canvas)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    override fun onDestroy() {
        runCatching {
            if (pingBound) unbindService(pingConnection)
        }
        pingBound = false
        pingService = null
        worker.shutdown()
        super.onDestroy()
    }
}
