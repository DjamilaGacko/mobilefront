package com.yele.mobilefront

import android.Manifest
import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Process
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.Calendar
import java.util.Locale

/// Consommation de données mobiles du mois et seuil mensuel (IMP-09).
///
/// Le volume vient de NetworkStatsManager, le compteur que tient Android pour
/// son propre écran « Consommation des données » : il couvre tout le
/// téléphone, toutes applications confondues, et survit aux redémarrages.
/// Sa lecture exige l'« accès aux données d'utilisation », une autorisation
/// spéciale que l'utilisateur accorde dans les réglages du système — aucune
/// fenêtre de demande n'existe pour elle.
///
/// Le seuil est conservé ici, côté natif, et non dans Hive : le moniteur en
/// direct doit pouvoir le vérifier sans que Flutter tourne.
object DataUsage {
    private const val PREFS = "yele_data"
    private const val KEY_LIMIT = "limitBytes"
    private const val KEY_WARNED = "warnedMonth"
    private const val KEY_ALERTED = "alertedMonth"
    const val KEY_MONITOR = "liveMonitor"

    private const val ALERT_CHANNEL = "yele_data_alerts"
    private const val ALERT_ID = 9101

    /// Part du seuil à laquelle un premier avertissement est donné.
    private const val WARN_RATIO = 0.8

    fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun limitBytes(ctx: Context): Long = prefs(ctx).getLong(KEY_LIMIT, 0L)

    /// 0 = pas de seuil. Un nouveau seuil réarme les alertes du mois : sinon,
    /// relever le seuil puis le dépasser à nouveau ne préviendrait plus.
    fun setLimitBytes(ctx: Context, bytes: Long) {
        prefs(ctx).edit()
            .putLong(KEY_LIMIT, bytes.coerceAtLeast(0L))
            .remove(KEY_WARNED)
            .remove(KEY_ALERTED)
            .apply()
    }

    fun hasUsageAccess(ctx: Context): Boolean {
        val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        @Suppress("DEPRECATION")
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        } else {
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /// Premier jour du mois en cours, 0 h, heure locale.
    fun monthStart(): Long = Calendar.getInstance().apply {
        set(Calendar.DAY_OF_MONTH, 1)
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    private fun monthKey(): String {
        val c = Calendar.getInstance()
        return String.format(Locale.ROOT, "%04d-%02d", c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1)
    }

    /// Octets mobiles reçus + envoyés par le téléphone depuis le début du
    /// mois, ou null sans l'accès aux données d'utilisation.
    fun monthMobileBytes(ctx: Context): Long? {
        if (!hasUsageAccess(ctx)) return null
        return try {
            val nsm = ctx.getSystemService(Context.NETWORK_STATS_SERVICE) as NetworkStatsManager
            @Suppress("DEPRECATION")
            val bucket = nsm.querySummaryForDevice(
                ConnectivityManager.TYPE_MOBILE, subscriberId(ctx), monthStart(), System.currentTimeMillis()
            )
            bucket.rxBytes + bucket.txBytes
        } catch (e: Exception) {
            null
        }
    }

    /// Identifiant d'abonné exigé jusqu'à Android 9. Depuis Android 10, il est
    /// réservé aux opérateurs et null désigne tous les réseaux mobiles.
    @Suppress("DEPRECATION")
    private fun subscriberId(ctx: Context): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return null
        return try {
            (ctx.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager).subscriberId
        } catch (e: SecurityException) {
            null
        }
    }

    /// Compare la consommation au seuil et prévient, une seule fois par mois,
    /// à 80 % puis à 100 %. [fallbackBytes] sert quand le compteur du
    /// téléphone est illisible : l'application passe alors la consommation de
    /// ses propres tests.
    fun checkLimit(ctx: Context, fallbackBytes: Long? = null): Map<String, Any?> {
        val used = monthMobileBytes(ctx) ?: fallbackBytes
        val limit = limitBytes(ctx)
        var notified: String? = null
        if (used != null && limit > 0) {
            val month = monthKey()
            val p = prefs(ctx)
            if (used >= limit && p.getString(KEY_ALERTED, null) != month) {
                notify(ctx, "Seuil de données dépassé",
                    "${format(used)} consommés ce mois-ci, pour un seuil de ${format(limit)}.")
                p.edit().putString(KEY_ALERTED, month).putString(KEY_WARNED, month).apply()
                notified = "limit"
            } else if (used < limit && used >= limit * WARN_RATIO && p.getString(KEY_WARNED, null) != month) {
                notify(ctx, "80 % de votre seuil de données",
                    "${format(used)} consommés sur ${format(limit)} ce mois-ci.")
                p.edit().putString(KEY_WARNED, month).apply()
                notified = "warning"
            }
        }
        return mapOf("used" to used, "limit" to limit, "notified" to notified)
    }

    private fun notify(ctx: Context, title: String, text: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(
                ALERT_CHANNEL, "Seuil de données", NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Alerte quand la consommation mensuelle approche du seuil fixé" })
        }
        val open = PendingIntent.getActivity(
            ctx, 0,
            Intent(ctx, MainActivity::class.java).putExtra(MainActivity.EXTRA_ROUTE, "/data"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        nm.notify(ALERT_ID, NotificationCompat.Builder(ctx, ALERT_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_data)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build())
    }

    /// Même présentation que côté Flutter : unités décimales, virgule.
    fun format(bytes: Long): String {
        val b = bytes.toDouble()
        return when {
            b < 1e6 -> "${Math.round(b / 1e3)} Ko"
            b < 1e9 -> {
                val mo = b / 1e6
                if (mo < 10) String.format(Locale.FRANCE, "%.1f Mo", mo) else "${Math.round(mo)} Mo"
            }
            else -> String.format(Locale.FRANCE, "%.2f Go", b / 1e9)
        }
    }
}
