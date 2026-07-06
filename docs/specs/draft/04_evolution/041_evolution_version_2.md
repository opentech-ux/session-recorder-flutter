# 041 - Évolution version 2

## Statut

Draft

## But

Ce document regroupe les recommandations issues de la revue de la V2 refactorisée du package `SessionRecorder`.
Il ne décrit pas l'état stable du SDK : il liste les évolutions supplémentaires à traiter avant ou après publication sur Dart pub.

Quand une évolution est implémentée, elle doit être retirée de ce fichier et reportée dans la spec stable correspondante.

## Contexte de revue

La V2 est une refonte nette de la V1 :

- suppression des anciens `delegates` et `services` très couplés ;
- introduction d'un runtime plus clair (`core`, `session`, `collectors`, `tree`, `models`) ;
- surface publique réduite ;
- séparation plus saine entre capture, stockage en mémoire et reporting ;
- meilleure base pour une architecture modulaire.

Le tag `session_recorder-v1.1.1` existe localement et le diff vers la branche actuelle montre une refonte importante du package.
La revue ci-dessous se concentre sur la logique actuelle de la V2 et sur son alignement avec les specs.

## Validation effectuée

- Lecture des specs `01_context`, `02_architecture`, `03_features` et `04_evolution`.
- Revue des modules `session`, `core`, `collectors`, `tree`, `models`, `observers`, `controllers`.
- Consultation du tag `session_recorder-v1.1.1` sans checkout.
- Tentative de validation statique :
  - `flutter analyze` : timeout après 120 secondes ;
  - `flutter analyze --no-pub` : timeout après 120 secondes ;
  - `dart analyze lib test` : timeout après 120 secondes.

La validation statique reste donc à refaire dans un environnement local stable avant publication.

## Synthèse

La V2 est structurellement beaucoup plus saine que la V1 et correspond bien à la direction décrite dans les specs.
Le découpage actuel est une bonne base pour publier une version 2, mais il reste plusieurs points à traiter avant de la considérer stable pour Dart pub.

Les sujets les plus importants ne sont pas des refactors massifs : ils concernent surtout la fiabilité du reporting, la précision des événements, la cohérence de publication et la couverture de tests.

## Priorité P0 - À traiter avant publication pub

### Mettre à jour README, CHANGELOG et exemples publics

État actuel :

- Le `README.md` décrit encore l'API V1 (`SessionRecorder.instance`, `SessionRecorderParams`, `SessionRecorderObserver`).
- Le code V2 expose `SessionRecorder.init`, `SessionRecorderConfig`, `SessionNavigatorObserver` et `SessionRecorderWidget`.
- Le `CHANGELOG.md` ne contient pas encore d'entrée `2.0.0`.

Risque :

- Un utilisateur pub.dev suivra une documentation qui ne compile pas avec la V2.

Cible :

- Mettre à jour le README avec l'intégration V2.
- Ajouter une entrée `2.0.0` au changelog.
- Ajouter un exemple minimal qui compile avec l'API publique actuelle.
- Aligner les exemples d'endpoint avec la politique réelle de validation.

### Stabiliser la validation de publication

État actuel :

- Les commandes d'analyse n'ont pas terminé dans la session de revue.
- Le dossier `test/` contient seulement un test vide.

Risque :

- La publication peut échouer lors d'un dry-run pub.
- Des régressions critiques peuvent passer sans signal.

Cible :

- Faire passer `flutter analyze`.
- Faire passer `flutter test`.
- Faire passer `dart pub publish --dry-run` ou `flutter pub publish --dry-run`.
- Ajouter des tests de sérialisation, collectors, LOM, lifecycle et reporting.

### Clarifier la compatibilité SDK Flutter/Dart

État actuel :

- `pubspec.yaml` indique `sdk: ^3.9.0`.
- `flutter: ">=1.17.0"` est beaucoup plus large et probablement trompeur.

Risque :

- Le package se présente comme compatible avec de vieux Flutter, mais exige en pratique un SDK Dart récent.

Cible :

- Définir un minimum Flutter cohérent avec Dart 3.9.
- Documenter clairement cette compatibilité dans README et pubspec.

### Corriger ou assumer la validation d'endpoint

État actuel :

- `SessionRecorderConfig.validate()` existe.
- Son appel est commenté dans `SessionRecorder.init`.
- La regex force `https://[subdomain].ux-key.com/endpoint`.
- Plusieurs exemples utilisent encore `api.example.com`.

Risque :

- Le SDK accepte une configuration invalide jusqu'au moment du reporting.
- `Uri.parse` peut échouer hors du bloc `try` du reporter.
- Les exemples et le comportement réel ne disent pas la même chose.

Cible :

- Décider si l'endpoint doit être strictement `ux-key.com` ou générique.
- Réactiver la validation ou supprimer la promesse de validation.
- Placer le parsing d'URI dans une zone protégée.
- Mettre à jour les specs et exemples.

### Rendre le reporter robuste

État actuel :

- Le `Timer.periodic` appelle `_flush()` sans garde de concurrence.
- Un flush lent peut chevaucher le flush suivant.
- Il n'y a pas de timeout HTTP explicite.
- `IOClient` n'est jamais fermé.
- En cas d'échec d'envoi, le chunk est déjà extrait et perdu.

Risque :

- Envois concurrents.
- Ressources réseau conservées.
- Requêtes suspendues trop longtemps.
- Perte de données plus forte que nécessaire.

Cible :

- Ajouter un verrou `_isFlushing`.
- Ajouter un timeout explicite à la requête HTTP.
- Ajouter une méthode `dispose` ou `close` au reporter.
- Décider si les chunks échoués doivent être définitivement jetés ou conservés en mémoire courte.
- Encapsuler tout le chemin de `_send`, y compris `Uri.parse`, dans le `try`.

### Éviter la double capture drag/scroll

État actuel :

- `Listener` voit tous les mouvements pointeur.
- `NotificationListener<ScrollNotification>` voit les scrolls.
- Un scroll tactile peut donc produire à la fois des `DragExplorationEvent` et des `ScrollExplorationEvent`.

Risque :

- Les données comportementales surestiment les explorations.
- Le backend doit deviner si un drag est un vrai drag ou un scroll déjà capturé.

Cible :

- Ajouter une coordination entre `ScrollCollector` et `GestureCollector`.
- Marquer un pointeur comme scrollable lorsque le scroll démarre.
- Supprimer ou reclassifier le drag correspondant.
- Tester les cas scroll vertical, scroll horizontal, nested scroll et drag hors scrollable.

### Résoudre le problème `LomRef` et `zone`

État actuel :

- `ContextImpl.recordLom` remplace `_currentLom` par le dernier `LomAbstract`.
- Un `LomRef` peut ne pas contenir de `root`.
- `TapTreeFinder` ne peut pas résoudre de zone sans `root`.
- Les actions retombent alors à `z0`.

Risque :

- Sur un écran déjà vu et dédupliqué, les actions perdent leur zone précise.

Cible :

- Garder un cache local `lomId -> Root` ou `signature -> Root`.
- Envoyer un `LomRef` léger dans le payload, mais conserver localement l'arbre complet pour le hit-test.
- Ne pas remplacer le LOM courant résoluble par un `LomRef` sans `root`.

### Vérifier la capture après pop de navigation

État actuel :

- `didPop` appelle `_handleCapture(previousRoute)`.
- Pour une transition pop, l'animation importante peut être celle de la route poppée, pas celle de `previousRoute`.

Risque :

- La capture LOM après retour écran peut arriver avant la fin réelle de l'animation.

Cible :

- Tester push, pop, replace et nested navigators.
- Pour `didPop`, attendre la fin de l'animation inverse de la route retirée si nécessaire.
- Ajouter un test widget dédié aux transitions de route.

## Priorité P1 - À traiter avant une V2 stable

### Revoir le hook global `onBuildScheduled`

État actuel :

- `TreeDetector` remplace `BuildOwner.onBuildScheduled`.
- Le hook précédent est appelé, mais il n'existe pas de restauration explicite.
- Le SDK ne possède pas de méthode de dispose globale.

Risque :

- Effets de bord dans les scénarios hot restart, tests widget, remount ou désactivation future.

Cible :

- Ajouter un cycle de vie clair au detector.
- Restaurer `onBuildScheduled` lors d'un stop/dispose.
- Documenter que le SDK est conçu pour vivre pendant toute la durée du processus.

### Adapter la règle de cooldown LOM pour la navigation

État actuel :

- Le cooldown de 400 ms s'applique aussi aux captures venant de la navigation.

Risque :

- Une mutation UI juste avant une navigation peut empêcher la capture du nouvel écran.

Cible :

- Donner priorité aux captures de navigation.
- Ou utiliser un cooldown séparé pour navigation et mutations UI.

### Clarifier la politique de déduplication LOM

État actuel :

- Si une signature existe dans le cache, `LomTreeInspector` retourne un `LomRef`.
- Le check `_lastSignature` arrive après le cache et ne bloque donc pas les signatures connues.

Question :

- Une signature identique consécutive doit-elle produire un `LomRef` ou être ignorée ?

Cible :

- Décider la règle produit.
- Mettre le code, les specs et les tests en accord.

### Corriger les priorités de `LomTreeConfig`

État actuel :

- `TextFormField` est présent dans `noiseAt` et dans `semantics`.
- `noiseAt` est évalué avant `semantics`.

Risque :

- Certains widgets sémantiques peuvent être aplatis alors qu'ils devraient rester comme zones.

Cible :

- Définir une priorité claire : `pruneAt`, `semantics`, `noiseAt`, `ignoreAt`, ou autre ordre explicite.
- Tester `TextField`, `TextFormField`, boutons, images, icônes et gestes custom.

### Ajuster la détection double tap

État actuel :

- Le premier tap est enregistré immédiatement.
- Le second tap peut ensuite produire un `doubleTap`.

Risque :

- Un double tap produit `tap + doubleTap`.

Cible :

- Décider si ce comportement est voulu.
- Si non, retarder l'émission du tap jusqu'à expiration de la fenêtre double tap.

### Dédupliquer le dernier point du sampling

État actuel :

- `_samplePositions` ajoute toujours le dernier point.
- Si le dernier point a déjà été ajouté par le seuil temporel, il peut être dupliqué.

Risque :

- Trajectoires légèrement bruitées ou points répétés.

Cible :

- Ajouter le dernier point seulement s'il est différent du dernier point échantillonné.

### Nettoyer les APIs internes no-op

État actuel :

- `NoOpContext.currentRouteElement` lance `UnimplementedError`.

Risque :

- Une API no-op devrait absorber les appels sans exception.

Cible :

- Retourner `null` au lieu de throw.
- Ajouter un test de non-crash avant initialisation.

### Libérer les callbacks et ressources au dispose

État actuel :

- `SessionRecorderWidget.dispose` draine les collectors.
- Le controller conserve potentiellement la callback d'interruption.
- Le reporter ne ferme pas son client HTTP.

Cible :

- Ajouter une stratégie de dispose interne.
- Nettoyer `onInterrupt(null)` quand le widget est détruit.
- Fermer le client HTTP quand le SDK s'arrête définitivement.

## Priorité P2 - Améliorations de qualité et maintenance

### Réduire le poids du package

État actuel :

- `assets/uxkey.png` est inclus dans le package via `pubspec.yaml`.
- Plusieurs modèles ou constantes semblent inutilisés (`RouteRecorded`, `NavigationType`, `ViewportPosition`, `ScrollSession`, certains seuils).

Cible :

- Supprimer les assets non nécessaires au runtime.
- Supprimer ou documenter les modèles internes inutilisés.
- Garder le package léger à installer.

### Aligner la documentation technique interne

État actuel :

- Certains commentaires Dartdoc gardent des formulations V1 ou contradictoires.
- Exemple : `init` est montré avant `runApp`, mais un commentaire indique aussi de l'appeler après montage de l'app root.

Cible :

- Harmoniser Dartdoc, README et specs.
- Garder une seule histoire d'intégration.

### Préparer l'architecture plugin

État actuel :

- La V2 est mieux découpée, mais il n'existe pas encore de contrat de plugin.

Cible :

- Définir un contrat minimal pour les futurs plugins.
- Décider si un plugin produit des records, observe le runtime ou enrichit le chunk.
- Garder le reporting centralisé.

### Ajouter `lom_ref`

État actuel :

- Les événements n'ont pas encore de `lom_ref`.

Cible :

- Ajouter `:lom_ref` en fin de chaîne `ae` et `ee`.
- Stocker le LOM actif au moment de la capture, pas seulement au moment du flush.
- Tester les changements de route entre capture événement et envoi.

### Implémenter `pnt`

État actuel :

- `pnt` reste vide.

Cible :

- Ajouter un collector de métriques peu coûteux.
- Déterminer si les métriques sont capturées périodiquement ou résumées par chunk.
- Ne jamais bloquer le thread UI.

## Tests recommandés

### Tests unitaires

- `Chunk.toMap` et `toJson`.
- `ActionEvent.concatenateString`.
- `ExplorationEvent.concatenateString`.
- `Lom`, `LomRef` et `Root.toMap`.
- `LomTreeHasher` avec tolérance géométrique.
- Sampling drag/pinch sans doublon final.
- `InactivityDetector` avec timers contrôlés.

### Tests widget

- `SessionRecorderWidget` installé une seule fois.
- Capture tap avec zone résolue.
- Double tap.
- Long press.
- Drag hors scrollable.
- Scroll sans double capture drag.
- Navigation push/pop/replace avec capture LOM après animation.
- Capture mutation UI avec debounce/cooldown.

### Tests réseau

- Chunk vide non envoyé.
- `shouldSend == false`.
- Endpoint invalide.
- Réponse HTTP non-2xx.
- Timeout.
- Flush concurrent.
- Lifecycle suspendu avec drain sans flush urgent.

### Tests de publication

- `flutter analyze`.
- `flutter test`.
- `dart pub publish --dry-run` ou `flutter pub publish --dry-run`.
- Vérification README avec l'API V2.
- Vérification CHANGELOG `2.0.0`.

## Conclusion

La V2 est proche d'une base publiable, mais elle ne doit pas encore être considérée comme stable sans traiter les points P0.
Les algorithmes actuels sont globalement raisonnables pour une première V2, mais les deux risques fonctionnels les plus importants sont la double capture drag/scroll et la perte de `zone` lorsque le LOM courant devient un `LomRef` sans arbre local.

