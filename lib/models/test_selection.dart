/// Sélection des tests à exécuter, choisie par l'utilisateur avant le lancement.
///
/// Chaque test est indépendant : on peut lancer le débit seul, le streaming
/// seul, la navigation seule, ou les trois ensemble (« test complet »).
class TestSelection {
  final bool speed; // débit : download / ping / upload
  final bool streaming; // lecture vidéo
  final bool browsing; // navigation web

  const TestSelection({
    this.speed = true,
    this.streaming = false,
    this.browsing = false,
  });

  /// Test complet : les trois mesures.
  const TestSelection.all() : this(speed: true, streaming: true, browsing: true);

  /// Au moins un test est sélectionné.
  bool get isEmpty => !speed && !streaming && !browsing;
}
