package com.yele.mobilefront

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.net.TrafficStats
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import java.util.Locale

/// Moniteur de débit en direct (IMP-09) : le débit instantané du téléphone,
/// affiché en permanence dans la barre d'état, comme le fait nPerf.
///
/// Activé uniquement à la demande de l'utilisateur, depuis l'écran
/// « Consommation data ». Pour ménager la batterie, il ne fait que lire deux
/// compteurs du système chaque seconde — aucun trafic réseau — et se met en
/// pause quand l'écran est éteint, puisque personne ne regarde alors la
/// barre d'état.
class LiveSpeedService : Service() {

    companion object {
        private const val CHANNEL = "yele_live_speed"
        private const val NOTIFICATION_ID = 9102
        private const val ACTION_STOP = "com.yele.mobilefront.STOP_LIVE"
        private const val TICK_MS = 1000L
        /// Le seuil mensuel est revérifié toutes les minutes.
        private const val LIMIT_EVERY_TICKS = 60

        @Volatile
        var running = false
            private set

        fun start(ctx: Context) {
            DataUsage.prefs(ctx).edit().putBoolean(DataUsage.KEY_MONITOR, true).apply()
            val intent = Intent(ctx, LiveSpeedService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(intent)
            } else {
                ctx.startService(intent)
            }
        }

        fun stop(ctx: Context) {
            DataUsage.prefs(ctx).edit().putBoolean(DataUsage.KEY_MONITOR, false).apply()
            ctx.stopService(Intent(ctx, LiveSpeedService::class.java))
        }

        fun wanted(ctx: Context) = DataUsage.prefs(ctx).getBoolean(DataUsage.KEY_MONITOR, false)
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastRx = 0L
    private var lastTx = 0L
    private var lastAt = 0L
    private var ticks = 0
    private var monthLine = ""

    private val tick = object : Runnable {
        override fun run() {
            update()
            handler.postDelayed(this, TICK_MS)
        }
    }

    private val screen = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> handler.removeCallbacks(tick)
                Intent.ACTION_SCREEN_ON -> {
                    resetCounters() // sans quoi le premier écart couvrirait toute la pause
                    handler.removeCallbacks(tick)
                    handler.post(tick)
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stop(this)
            return START_NOT_STICKY
        }
        createChannel()
        val first = build(0.0, 0.0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, first, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, first)
        }
        if (!running) {
            running = true
            // Diffusions du système uniquement : aucune autre application
            // n'a à joindre ce récepteur.
            ContextCompat.registerReceiver(this, screen, IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
            }, ContextCompat.RECEIVER_NOT_EXPORTED)
            resetCounters()
            ticks = 0
            handler.post(tick)
        }
        // Relancé par le système s'il doit le tuer faute de mémoire.
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        if (running) {
            try { unregisterReceiver(screen) } catch (_: Exception) {}
        }
        running = false
        super.onDestroy()
    }

    private fun resetCounters() {
        lastRx = TrafficStats.getTotalRxBytes()
        lastTx = TrafficStats.getTotalTxBytes()
        lastAt = SystemClock.elapsedRealtime()
    }

    private fun update() {
        val rx = TrafficStats.getTotalRxBytes()
        val tx = TrafficStats.getTotalTxBytes()
        val now = SystemClock.elapsedRealtime()
        val seconds = (now - lastAt) / 1000.0
        if (seconds <= 0 || rx < 0 || tx < 0) return
        // Mb/s : octets × 8 / 1 000 000. Un compteur qui recule (changement de
        // réseau) donnerait un débit négatif : on l'ignore.
        val down = ((rx - lastRx).coerceAtLeast(0) * 8 / 1e6) / seconds
        val up = ((tx - lastTx).coerceAtLeast(0) * 8 / 1e6) / seconds
        lastRx = rx; lastTx = tx; lastAt = now

        if (ticks % LIMIT_EVERY_TICKS == 0) {
            val r = DataUsage.checkLimit(this)
            val used = r["used"] as Long?
            val limit = r["limit"] as Long
            monthLine = when {
                used == null -> ""
                limit > 0 -> "Ce mois-ci : ${DataUsage.format(used)} sur ${DataUsage.format(limit)}"
                else -> "Ce mois-ci : ${DataUsage.format(used)}"
            }
        }
        ticks++

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, build(down, up))
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // IMPORTANCE_LOW : ni son ni bandeau, la notification se met à jour
        // chaque seconde sans jamais déranger.
        nm.createNotificationChannel(NotificationChannel(
            CHANNEL, "Débit en direct", NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Débit instantané affiché dans la barre d'état"
            setShowBadge(false)
        })
    }

    private fun build(down: Double, up: Double): Notification {
        val open = PendingIntent.getActivity(
            this, 1,
            Intent(this, MainActivity::class.java).putExtra(MainActivity.EXTRA_ROUTE, "/data"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stop = PendingIntent.getService(
            this, 2,
            Intent(this, LiveSpeedService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }
        return b
            .setSmallIcon(speedIcon(down))
            .setContentTitle("▼ ${mbps(down)}   ▲ ${mbps(up)}")
            .setContentText(monthLine.ifEmpty { "Débit en direct" })
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_STATUS)
            .addAction(Notification.Action.Builder(null as Icon?, "Arrêter", stop).build())
            .build()
    }

    private fun mbps(v: Double): String = when {
        v < 0.1 -> String.format(Locale.FRANCE, "%.0f kb/s", v * 1000)
        v < 10 -> String.format(Locale.FRANCE, "%.1f Mb/s", v)
        else -> String.format(Locale.FRANCE, "%.0f Mb/s", v)
    }

    /// Icône de barre d'état dessinée à la volée : le débit descendant sur
    /// deux lignes (valeur, unité). Android n'affiche les petites icônes qu'en
    /// silhouette blanche ; seul le canal alpha compte.
    private fun speedIcon(down: Double): Icon {
        val size = (24 * resources.displayMetrics.density).toInt().coerceAtLeast(48)
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val (value, unit) = when {
            down < 1 -> Pair(String.format(Locale.ROOT, "%.0f", down * 1000), "kb/s")
            down < 10 -> Pair(String.format(Locale.FRANCE, "%.1f", down), "Mb/s")
            else -> Pair(String.format(Locale.ROOT, "%.0f", down), "Mb/s")
        }
        paint.textSize = size * 0.58f
        // Réduit la police si la valeur déborde (« 120 », « 999 »).
        while (paint.measureText(value) > size && paint.textSize > size * 0.3f) {
            paint.textSize -= 1f
        }
        canvas.drawText(value, size / 2f, size * 0.58f, paint)
        paint.textSize = size * 0.36f
        paint.typeface = Typeface.DEFAULT
        canvas.drawText(unit, size / 2f, size * 0.96f, paint)
        return Icon.createWithBitmap(bmp)
    }
}
