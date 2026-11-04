# Yélé — Application mobile

Application Flutter de mesure de la qualité des réseaux mobiles au Burkina Faso.
Elle mesure le débit, la latence, la qualité du streaming vidéo et le temps de
chargement des pages web, puis remonte chaque mesure géolocalisée vers le
backend Yélé. Ces mesures alimentent la carte publique de couverture.

---

## Le projet Yélé en un coup d'œil

Yélé est composé de quatre dépôts indépendants :

| Dépôt | Rôle | Techno |
|---|---|---|
| **`mobilefront`** *(ce dépôt)* | Application mobile : réalise les mesures sur le terrain | Flutter / Dart |
| `mobiletest` | Backend : serveur de speedtest, réception des mesures, API du tableau de bord | Go + MongoDB |
| `new_web` | Tableau de bord public : carte, statistiques, comparaison des opérateurs | HTML/CSS/JS |
| `ai` | Micro-service d'analyse : détection d'anomalies et prévision de qualité | Python / FastAPI |

Le parcours d'une mesure :

```
  [ Application mobile ]                   ce dépôt
       |
       |  1. mesure le débit contre le serveur (/garbage, /empty)
       |  2. envoie le résultat + contexte (opérateur, GPS, techno radio)
       v
  POST /results/telemetry
       |
       v
  [ Backend Go ] ---- stocke ----> [ MongoDB Atlas ]
       |                                  ^
       |  GET /api/dashboard/*            | lit les mesures
       v                                  |
  [ Tableau de bord web ]           [ Service IA ]
```

---

## Prérequis

- **Flutter SDK >= 3.12** (canal stable) — vérifier avec `flutter --version`
- **Android Studio** ou le SDK Android en ligne de commande
- Un appareil Android physique **recommandé** : un émulateur ne donne ni signal
  radio réel, ni opérateur SIM, ni position GPS crédible — les mesures y sont
  donc peu représentatives.

## Démarrage rapide

```bash
git clone <url-du-depot>
cd mobilefront

flutter pub get

# Génère le code Hive (modèle de stockage local)
dart run build_runner build --delete-conflicting-outputs

flutter run
```

L'application pointe par défaut sur le backend de démonstration hébergé sur
Render. Aucune configuration n'est nécessaire pour un premier lancement.

## Configuration

Tout est centralisé dans **`lib/constants/config.dart`**.

| Constante | Rôle | Défaut |
|---|---|---|
| `API_BASE_URL` | URL du backend Go | `https://mobiletest-j0c6.onrender.com` |
| `SPEED_PHASE_DURATION_SEC` | Durée d'une phase de mesure de débit | `10` s |
| `SPEED_WARMUP_MS` | Montée en charge exclue du calcul | `1000` ms |
| `STREAMING_YOUTUBE_VIDEO_ID` | Vidéo de référence du test streaming | `aqz-KE-bpKQ` |
| `BROWSING_REFERENCE_PAGES` | Pages du test de navigation | 6 sites dont `lefaso.net` |

Pour pointer sur un backend local :

```dart
const String API_BASE_URL = 'http://10.0.2.2:8989';  // émulateur Android
// const String API_BASE_URL = 'http://192.168.1.42:8989';  // appareil physique
```

> `10.0.2.2` est l'adresse par laquelle l'émulateur Android voit la machine
> hôte. Depuis un téléphone réel, il faut l'adresse IP de la machine sur le
> réseau local.

## Structure du code

```
lib/
├── main.dart                    Point d'entrée, définition des routes
├── constants/
│   ├── config.dart              TOUTE la configuration (URL, seuils, cadences)
│   └── app_colors.dart          Palette et styles de texte
├── models/
│   ├── speed_test_result.dart   Modèle principal (persisté via Hive)
│   └── test_selection.dart      Quels tests lancer (débit / streaming / web)
├── screens/
│   ├── full_test_screen.dart    Écran de test — paramétré par TestSelection
│   ├── score_screen.dart        Résultat détaillé
│   ├── history_screen.dart      Historique local
│   ├── coverage_screen.dart     Carte de couverture
│   └── settings_screen.dart     Réglages
├── services/
│   ├── speed_test_api_service.dart         Moteur de mesure du débit
│   ├── streaming_test_service.dart         Test de streaming YouTube
│   ├── browsing_test_service.dart          Test de navigation web
│   ├── test_reminder_service.dart          Rappels de test (notifications)
│   ├── network_info_service.dart           Opérateur, techno radio, signal
│   ├── location_service.dart               Position GPS
│   └── local_storage_service.dart          Persistance Hive
└── widgets/                     Composants réutilisables

android/app/src/main/kotlin/com/yele/mobilefront/
└── MainActivity.kt              Canal de méthode `com.yele/telephony`
                                 (opérateur SIM, techno radio, compteur d'octets)
```

---

## Comprendre les trois moteurs de mesure

### 1. Le débit — `speed_test_api_service.dart`

La mesure se fait sur une **durée fixe (10 s)** et non sur une taille de fichier
fixe. C'est un choix délibéré : sur un lien rapide, quelques mégaoctets sont
transférés en une fraction de seconde, ce qui ne mesure que le démarrage lent de
TCP et ne laisse rien voir à l'écran.

Deux précautions donnent des chiffres comparables d'un test à l'autre :

- La **première seconde est exclue** du calcul (`SPEED_WARMUP_MS`) : c'est la
  montée en charge de TCP, elle sous-estime systématiquement le débit réel.
- Une **pause de 1,2 s** sépare la fin de l'upload de la mesure de latence
  (`LATENCY_SETTLE_MS`), le temps que les files d'attente du réseau se vident.
  Sans elle, le ping mesuré est celui d'un réseau saturé par le test lui-même
  (bufferbloat), pas celui du réseau au repos.

### 2. Le streaming — `streaming_test_service.dart`

Plutôt que d'estimer la qualité vidéo à partir du débit, le test **lit réellement
une vidéo YouTube** dans une WebView via l'IFrame Player API. Il demande
successivement 720p, 1080p puis 2160p et mesure ce que le réseau tient
effectivement : temps de démarrage, nombre de coupures, résolution maximale
atteinte. C'est l'approche utilisée par nPerf.

> La vidéo de référence **doit** être disponible en 2160p, sinon la colonne 4K
> restera systématiquement vide. Vérifier `STREAMING_YOUTUBE_VIDEO_ID` avant
> toute mise en production.

### 3. La navigation web — `browsing_test_service.dart`

Charge six pages de référence et mesure le temps de chargement, selon le critère
ARCEP : une page est considérée correctement chargée en **moins de 10 secondes**.

---

## Les rappels de test

L'utilisateur peut demander, depuis les réglages, un rappel l'invitant à lancer
un test toutes les trois heures. Un appui sur la notification ouvre directement
le speedtest.

**Rien ne tourne en arrière-plan.** L'échéance est déposée auprès du système
(AlarmManager sur Android, centre de notifications sur iOS), qui réveille
l'utilisateur au moment voulu ; l'application dort d'ici là. C'est ce qui rend
ces rappels possibles sur iOS comme sur Android.

**L'heure exacte n'est pas garantie, et c'est délibéré.** Planifier à la minute
près exige depuis Android 12 la permission `SCHEDULE_EXACT_ALARM`, que Google
réserve aux réveils, agendas et rappels de médicaments — un rappel de test n'y
a pas droit. Les rappels utilisent donc une alarme inexacte et peuvent arriver
avec quelques dizaines de minutes de décalage. Ne pas chercher à contourner ce
point : la demande serait refusée à la publication.

**Deux prérequis de compilation** faciles à casser sans s'en apercevoir :

- `isCoreLibraryDesugaringEnabled` dans `android/app/build.gradle.kts` — le
  plugin s'appuie sur `java.time` ; sans lui la compilation échoue.
- `android/app/src/main/res/raw/keep.xml` — `isShrinkResources` supprimerait
  l'icône de la notification, qui n'est désignée que par son nom à l'exécution.
  Les notifications cesseraient alors de s'afficher **en release uniquement**,
  sans aucun message d'erreur.

### Permissions Android

| Permission | Pourquoi |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE` | Mesures et type de connexion |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | Géolocaliser chaque mesure |
| `READ_PHONE_STATE` | Opérateur SIM et technologie radio |
| `POST_NOTIFICATIONS` | Rappels de test (Android 13+) |
| `RECEIVE_BOOT_COMPLETED` | Replanifier les rappels après un redémarrage |

L'application ne tourne jamais en arrière-plan : toutes les mesures sont
déclenchées par l'utilisateur, application ouverte. Les rappels eux-mêmes ne
font tourner aucun code — l'échéance est confiée au système.

---

## Compilation

```bash
flutter build apk --release            # APK universel
flutter build appbundle --release      # Bundle pour le Play Store
```

L'intégration continue est décrite dans **`codemagic.yaml`** (Codemagic).
Identifiant d'application : `com.yele.mobilefront`.

## Tests

```bash
flutter test
flutter analyze
```

> La couverture de tests est actuellement minimale (`test/widget_test.dart`).
> C'est le premier chantier ouvert aux contributions.

---

## Contribuer

Les contributions sont bienvenues. Quelques pistes concrètes :

- Étoffer les tests, en particulier autour des services de mesure.
- Support iOS pour les tests actifs.
- Traduction de l'interface (actuellement en français uniquement).
- Normaliser le nom d'opérateur renvoyé par `MainActivity.telephonyInfo()` :
  certains téléphones renvoient le code MCC+MNC (« 61301 ») en guise de nom, et
  `NetworkInfoService` ne consulte sa table de correspondance que lorsque le nom
  est *vide*, pas lorsqu'il est numérique. Le code brut se retrouve alors traité
  comme un opérateur à part entière dans les statistiques.

Merci d'ouvrir une *issue* décrivant le problème avant une *pull request*
importante.

## Licence

À définir avant l'ouverture publique du dépôt. Voir la note du dépôt
`mobiletest`, qui hérite de la licence LGPL-3.0 de LibreSpeed.
