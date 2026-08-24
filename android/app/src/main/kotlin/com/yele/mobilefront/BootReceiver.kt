package com.yele.mobilefront

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat

/**
 * Relance la collecte après un redémarrage du téléphone, si l'utilisateur ne
 * l'avait pas arrêtée lui-même.
 *
 * Limite connue : à partir d'Android 14, le système refuse le démarrage d'un
 * service de premier plan de type `location` depuis l'arrière-plan, y compris
 * au démarrage. La tentative échoue alors silencieusement et la collecte
 * reprend à la prochaine ouverture de l'application. C'est pourquoi l'échec
 * est ici absorbé plutôt que remonté : il est attendu sur ces versions.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!SignalCollectorService.prefs(context)
                .getBoolean(SignalCollectorService.KEY_ENABLED, false)
        ) return

        val service = Intent(context, SignalCollectorService::class.java)
            .setAction(SignalCollectorService.ACTION_START)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, service)
            } else {
                context.startService(service)
            }
        } catch (_: Exception) {
            // Démarrage refusé par le système : reprise au prochain lancement.
        }
    }
}
