package com.yele.mobilefront

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.TrafficStats
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellSignalStrengthLte
import android.telephony.CellSignalStrengthNr
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /// Écran Flutter à ouvrir, transmis par les notifications (IMP-09).
        const val EXTRA_ROUTE = "yele_route"
    }

    private val channelName = "com.yele/telephony"
    private val phonePermissionRequestCode = 1001
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Le moniteur de débit, activé avant un redémarrage du téléphone ou un
        // arrêt forcé de l'application, reprend à son ouverture.
        if (LiveSpeedService.wanted(this) && !LiveSpeedService.running) {
            try { LiveSpeedService.start(this) } catch (_: Exception) {}
        }

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel!!
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTelephony" -> result.success(telephonyInfo())
                    "requestPhonePermission" -> result.success(ensurePhonePermission())
                    // Lecture seule : l'écran des permissions doit pouvoir
                    // afficher l'état sans déclencher de demande à l'ouverture.
                    "checkPhonePermission" -> result.success(
                        ContextCompat.checkSelfPermission(
                            this, Manifest.permission.READ_PHONE_STATE
                        ) == PackageManager.PERMISSION_GRANTED
                    )
                    "getRxBytes" -> result.success(rxBytes())
                    "getTxBytes" -> result.success(txBytes())
                    "getAndroidId" -> result.success(androidId())
                    // ── Consommation data (IMP-09) ──
                    "getDataUsage" -> result.success(mapOf(
                        "deviceBytes" to DataUsage.monthMobileBytes(this),
                        "usageAccess" to DataUsage.hasUsageAccess(this),
                        "limitBytes" to DataUsage.limitBytes(this),
                        "monthStart" to DataUsage.monthStart(),
                    ))
                    "openUsageAccessSettings" -> {
                        startActivity(Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "setDataLimit" -> {
                        DataUsage.setLimitBytes(this, (call.argument<Number>("bytes") ?: 0).toLong())
                        result.success(null)
                    }
                    "checkDataLimit" -> result.success(
                        DataUsage.checkLimit(this, call.argument<Number>("fallbackBytes")?.toLong())
                    )
                    "setLiveMonitor" -> {
                        if (call.argument<Boolean>("on") == true) LiveSpeedService.start(this)
                        else LiveSpeedService.stop(this)
                        result.success(null)
                    }
                    "isLiveMonitorOn" -> result.success(LiveSpeedService.running)
                    // Écran demandé par la notification qui a lancé l'application.
                    "takeLaunchRoute" -> {
                        result.success(intent?.getStringExtra(EXTRA_ROUTE))
                        intent?.removeExtra(EXTRA_ROUTE)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Application déjà ouverte (launchMode singleTop) : la notification
    /// touchée arrive ici, et l'écran est ouvert directement côté Flutter.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(EXTRA_ROUTE)?.let { channel?.invokeMethod("openRoute", it) }
    }

    /// Retourne true si READ_PHONE_STATE est déjà accordée ; sinon déclenche la
    /// demande runtime (le résultat sera disponible aux prochaines lectures).
    private fun ensurePhonePermission(): Boolean {
        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.READ_PHONE_STATE
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.READ_PHONE_STATE), phonePermissionRequestCode
            )
        }
        return granted
    }

    /// Identifiant Android de l'application (IMP-15), ou null s'il est illisible.
    ///
    /// Depuis Android 8, cette valeur est propre au couple appareil + clé de
    /// signature de l'application : elle survit à une réinstallation, mais
    /// diffère d'une application à l'autre, ce qui empêche de croiser les
    /// données avec d'autres services. Elle n'est jamais transmise telle
    /// quelle : le code Dart n'en envoie qu'une empreinte.
    private fun androidId(): String? =
        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
            ?.takeIf { it.isNotBlank() }

    /// Octets reçus par l'application depuis le démarrage de l'appareil, ou -1
    /// si l'appareil ne tient pas ce compteur. Inclut le trafic du WebView : la
    /// pile réseau de Chromium tourne dans le processus de l'app, donc sous le
    /// même UID.
    private fun rxBytes(): Long {
        val bytes = TrafficStats.getUidRxBytes(Process.myUid())
        return if (bytes == TrafficStats.UNSUPPORTED.toLong()) -1L else bytes
    }

    /// Octets envoyés par l'application, ou -1. Pendant la phase d'upload d'un
    /// test, c'est l'essentiel du forfait consommé (IMP-01).
    private fun txBytes(): Long {
        val bytes = TrafficStats.getUidTxBytes(Process.myUid())
        return if (bytes == TrafficStats.UNSUPPORTED.toLong()) -1L else bytes
    }

    /// Informations de la SIM **effectivement utilisée pour les données**.
    ///
    /// Retourne { simOperator, mccMnc, cellularTech, simSlot, rsrp, rsrq,
    /// signalDbm } — chaque champ vaut null s'il est indisponible.
    private fun telephonyInfo(): Map<String, Any?> {
        val info = HashMap<String, Any?>()
        listOf("simOperator", "mccMnc", "cellularTech", "simSlot",
               "rsrp", "rsrq", "signalDbm")
            .forEach { info[it] = null }

        val base = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager ?: return info
        // ISS-02 : le TelephonyManager par défaut est lié à la SIM par défaut,
        // qui n'est PAS forcément celle des données. Sur un téléphone à deux
        // SIM, la mesure se retrouvait ainsi attribuée à la SIM 1 alors qu'elle
        // passait par la SIM 2.
        val tm = dataTelephonyManager(base)

        try {
            val name = tm.networkOperatorName?.trim()
            if (!name.isNullOrEmpty()) info["simOperator"] = name

            // MCC+MNC (ex. « 61301 ») — permet un rattachement fiable côté Dart
            // quand le nom commercial est absent ou vaut le code lui-même.
            val mccMnc = tm.networkOperator?.trim()
            if (!mccMnc.isNullOrEmpty()) info["mccMnc"] = mccMnc
        } catch (e: SecurityException) {
        } catch (e: Exception) {
        }

        // Emplacement physique de la SIM utilisée (0 = SIM 1). Sert à vérifier
        // ISS-02 sur le terrain : l'agent voit quelle SIM a réellement servi.
        info["simSlot"] = dataSimSlot()

        // Techno radio de la SIM de données, pas de la SIM par défaut.
        try {
            @Suppress("DEPRECATION")
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                tm.dataNetworkType
            } else {
                tm.networkType
            }
            info["cellularTech"] = techLabel(type)
        } catch (e: SecurityException) {
        } catch (e: Exception) {
        }

        readSignal(tm, info)

        // Android renvoie Int.MAX_VALUE pour une valeur radio indisponible :
        // transmise telle quelle, elle passerait pour une mesure aberrante.
        listOf("rsrp", "rsrq", "signalDbm").forEach {
            info[it] = sane(info[it] as? Int)
        }
        return info
    }

    /// TelephonyManager lié à l'abonnement qui porte les DONNÉES mobiles.
    ///
    /// Sans cela, tout est lu sur la SIM par défaut. `createForSubscriptionId`
    /// et `getDefaultDataSubscriptionId` existent depuis Android 7 ; en dessous,
    /// le double SIM n'est de toute façon pas géré uniformément et on garde
    /// l'instance par défaut.
    private fun dataTelephonyManager(base: TelephonyManager): TelephonyManager {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return base
        return try {
            val subId = SubscriptionManager.getDefaultDataSubscriptionId()
            if (subId == SubscriptionManager.INVALID_SUBSCRIPTION_ID) base
            else base.createForSubscriptionId(subId)
        } catch (e: Exception) {
            base
        }
    }

    /// Emplacement physique (0 = SIM 1) de la SIM portant les données, ou null.
    private fun dataSimSlot(): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null
        return try {
            val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                as? SubscriptionManager ?: return null
            val subId = SubscriptionManager.getDefaultDataSubscriptionId()
            if (subId == SubscriptionManager.INVALID_SUBSCRIPTION_ID) return null
            sm.getActiveSubscriptionInfo(subId)?.simSlotIndex
        } catch (e: SecurityException) {
            null // READ_PHONE_STATE manquante
        } catch (e: Exception) {
            null
        }
    }

    /// ISS-01 : puissance et qualité radio.
    ///
    /// RSRP (puissance du signal de référence, en dBm) et RSRQ (qualité, en dB)
    /// ne sont définis qu'en 4G et 5G — ils n'existent pas en 2G/3G, où seul un
    /// niveau global a un sens. Deux sources selon la version d'Android :
    /// `signalStrength` à partir d'Android 10, la liste des cellules avant.
    private fun readSignal(tm: TelephonyManager, info: HashMap<String, Any?>) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val strengths = tm.signalStrength?.cellSignalStrengths ?: emptyList()
                // Niveau et dBm généraux : la première mesure disponible, quelle
                // que soit la technologie.
                strengths.firstOrNull()?.let {
                    info["signalDbm"] = it.dbm
                }
                strengths.forEach { s ->
                    when (s) {
                        is CellSignalStrengthLte -> {
                            info["rsrp"] = s.rsrp
                            info["rsrq"] = s.rsrq
                        }
                        is CellSignalStrengthNr -> {
                            // La 5G prime si les deux sont présentes (NSA) :
                            // c'est elle qui porte le débit.
                            info["rsrp"] = s.ssRsrp
                            info["rsrq"] = s.ssRsrq
                        }
                    }
                }
            } catch (e: SecurityException) {
            } catch (e: Exception) {
            }
            if (info["rsrp"] != null) return
        }

        // Repli pour Android 8 et 9, ou si signalStrength n'a rien donné.
        // getAllCellInfo exige ACCESS_FINE_LOCATION en plus de READ_PHONE_STATE.
        try {
            @Suppress("DEPRECATION")
            val cells = tm.allCellInfo ?: return
            for (cell in cells) {
                if (!cell.isRegistered) continue // cellules voisines : hors sujet
                when {
                    cell is CellInfoLte -> {
                        val s = cell.cellSignalStrength
                        info["rsrp"] = s.rsrp
                        info["rsrq"] = s.rsrq
                        if (info["signalDbm"] == null) {
                            info["signalDbm"] = s.dbm
                        }
                        return
                    }
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && cell is CellInfoNr -> {
                        val s = cell.cellSignalStrength as? CellSignalStrengthNr ?: continue
                        info["rsrp"] = s.ssRsrp
                        info["rsrq"] = s.ssRsrq
                        if (info["signalDbm"] == null) {
                            info["signalDbm"] = s.dbm
                        }
                        return
                    }
                }
            }
        } catch (e: SecurityException) {
        } catch (e: Exception) {
        }
    }

    /// Android renvoie Int.MAX_VALUE quand une valeur radio est indisponible.
    /// Transmise telle quelle, elle apparaîtrait comme une mesure aberrante.
    private fun sane(value: Int?): Int? =
        if (value == null || value == Int.MAX_VALUE || value == Int.MIN_VALUE) null else value

    private fun techLabel(type: Int): String? {
        return when (type) {
            TelephonyManager.NETWORK_TYPE_GPRS,
            TelephonyManager.NETWORK_TYPE_EDGE,
            TelephonyManager.NETWORK_TYPE_CDMA,
            TelephonyManager.NETWORK_TYPE_1xRTT,
            TelephonyManager.NETWORK_TYPE_IDEN,
            TelephonyManager.NETWORK_TYPE_GSM -> "2G"

            TelephonyManager.NETWORK_TYPE_UMTS,
            TelephonyManager.NETWORK_TYPE_EVDO_0,
            TelephonyManager.NETWORK_TYPE_EVDO_A,
            TelephonyManager.NETWORK_TYPE_HSDPA,
            TelephonyManager.NETWORK_TYPE_HSUPA,
            TelephonyManager.NETWORK_TYPE_HSPA,
            TelephonyManager.NETWORK_TYPE_EVDO_B,
            TelephonyManager.NETWORK_TYPE_EHRPD,
            TelephonyManager.NETWORK_TYPE_HSPAP,
            TelephonyManager.NETWORK_TYPE_TD_SCDMA -> "3G"

            TelephonyManager.NETWORK_TYPE_LTE,
            TelephonyManager.NETWORK_TYPE_IWLAN -> "4G"

            TelephonyManager.NETWORK_TYPE_NR -> "5G"

            else -> null
        }
    }
}
