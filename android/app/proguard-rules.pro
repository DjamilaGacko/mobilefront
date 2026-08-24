# Règles R8 pour Yélé.
#
# R8 supprime tout code Java/Kotlin qu'il ne voit pas appelé. Les plugins
# Flutter sont instanciés par réflexion depuis le moteur : sans les règles
# ci-dessous, ils disparaissent du build release et l'application plante au
# démarrage — un plantage invisible en debug, qui n'active pas R8.

# ── Moteur Flutter ───────────────────────────────────────────────────────────
# Seules les classes appelées depuis le code natif (JNI) doivent être
# conservées nommément. Conserver tout io.flutter.** ferait grossir le dex
# sans rien protéger de plus : le reste est atteint par R8 normalement.
-keep class io.flutter.embedding.engine.FlutterJNI { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.embedding.engine.plugins.** { *; }

# ── WebView : tests de streaming et de navigation ────────────────────────────
# Les méthodes exposées au JavaScript sont appelées depuis la page, donc
# jamais référencées par du code Java.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class * extends android.webkit.WebChromeClient { *; }

# ── Play Core : composants différés, non utilisés ici ────────────────────────
# Le moteur Flutter référence PlayStoreDeferredComponentManager même quand
# l'application n'utilise pas les modules à la demande. La bibliothèque Play
# Core n'étant pas embarquée, R8 échoue sur ces classes absentes : on les
# ignore explicitement plutôt que d'ajouter une dépendance inutile.
-dontwarn com.google.android.play.core.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }

# ── Play Services : dépendance de localisation de geolocator ─────────────────
# Pas de -keep global : les classes réellement utilisées sont référencées
# directement par geolocator, donc conservées d'office. Un keep large ici
# retenait toute la bibliothèque et doublait la taille du dex.
-dontwarn com.google.android.gms.**

# ── Collecte passive : service et receiver déclarés au manifeste ─────────────
# Android les instancie par leur nom de classe ; R8 les renommerait sans cela.
-keep class com.yele.mobilefront.SignalCollectorService { *; }
-keep class com.yele.mobilefront.BootReceiver { *; }

# ── Annotations conservées (utilisées à l'exécution) ─────────────────────────
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Avertissements sans conséquence sur les API absentes du SDK Android.
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
