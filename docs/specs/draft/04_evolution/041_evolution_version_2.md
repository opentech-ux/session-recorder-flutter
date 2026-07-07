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

## Priorité P0 - Version 2

Statut : les points P0 ci-dessous ont été traités dans le runtime V2, sauf la validation complète par commandes locales, qui reste à refaire car les commandes Flutter/Dart ont expiré dans l'environnement de revue.

### Mettre à jour README, CHANGELOG et exemples publics

État actuel :

- Le `README.md` décrit l'API V2 réelle : `SessionRecorder.init`, `SessionRecorderConfig`, `SessionNavigatorObserver` et `SessionRecorderWidget`.
- Le `CHANGELOG.md` contient une entrée `2.0.0`.
- Les exemples utilisent le format d'endpoint strict.

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
- Le dossier `test/` contient des tests unitaires ciblés pour reporter, séparation de chunks, `LomRef` et sérialisation d'événements.

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

- `pubspec.yaml` indique `sdk: ">=3.0.0 <4.0.0"`.
- `flutter: ">=3.10.0"` est aligné avec Dart 3 et les constructions du code actuel.

Risque :

- Le package se présente comme compatible avec de vieux Flutter, mais exige en pratique un SDK Dart récent.

Cible :

- Définir un minimum Flutter cohérent avec Dart 3.9.
- Documenter clairement cette compatibilité dans README et pubspec.

### Corriger ou assumer la validation d'endpoint

Statut V2 :

- Cible V2 stricte : `SessionRecorder.init` doit appeler `SessionRecorderConfig.validate()` avant publication.
- Le format accepté en publication reste `https://[subdomain].ux-key.com/endpoint`.
- L'appel est temporairement commenté pendant les tests sur endpoint local.

État actuel :

- `SessionRecorderConfig.validate()` existe.
- Son appel est temporairement commenté dans `SessionRecorder.init`.
- La regex force `https://[subdomain].ux-key.com/endpoint`.
- Les exemples publics utilisent le format strict.

Risque :

- Le SDK accepte une configuration invalide jusqu'au moment du reporting.
- `Uri.parse` peut échouer hors du bloc `try` du reporter.
- Les exemples et le comportement réel ne disent pas la même chose.

Cible :

- Endpoint strict `ux-key.com` assumé pour la V2.
- Parsing d'URI protégé dans le reporter.
- Specs et exemples alignés.

### Rendre le reporter robuste

Statut V2 :

- Implémenté de manière minimaliste : garde anti-flush concurrent, timeout HTTP 5 secondes, file mémoire de 3 chunks et 1 retry.

État actuel :

- `_flush()` possède un garde de concurrence.
- La requête HTTP applique un timeout de 5 secondes.
- Une file mémoire courte conserve au maximum 3 chunks.
- Chaque chunk a droit à 1 retry.
- `IOClient` est fermé par le dispose interne du reporter.

Risque :

- Envois concurrents.
- Requêtes suspendues trop longtemps.
- Perte de données plus forte que nécessaire.

Cible :

- Garder le reporter non bloquant et sans persistance disque.
- Conserver `close()` comme cycle de vie interne, sans ajouter d'API publique.

### Assumer la séquence drag/scroll

Décision V2 :

- La séquence `scrollStart`, `drag...`, `scrollEnd` est conservée et représente une exploration de scroll.
- Les `drag` ne sont pas supprimés pendant un scroll, car ils portent la trajectoire utile.

État actuel :

- `Listener` voit tous les mouvements pointeur.
- `NotificationListener<ScrollNotification>` voit les scrolls.
- Un scroll tactile peut donc produire à la fois des `DragExplorationEvent` et des `ScrollExplorationEvent`.

Risque :

- Le backend doit interpréter explicitement `scrollStart`, `drag...`, `scrollEnd` comme une seule exploration de scroll.

Cible :

- Conserver cette règle dans les specs et les tests.
- Ne pas ajouter `scrollUpdate` dans cette étape.
- Garder un `drag` hors séquence scroll comme exploration autonome.

### Résoudre le problème `LomRef` et `zone`

Statut V2 :

- Implémenté : le contexte conserve localement les roots connus et utilise une version locale résoluble du `LomRef`.

État actuel :

- `ContextImpl` conserve un cache local `lomId -> Root`.
- Le payload continue à envoyer un `LomRef` léger.
- Le hit-test local utilise un `LomRef` enrichi avec son `root` connu.

Risque :

- Sur un écran déjà vu et dédupliqué, les actions perdent leur zone précise.

Cible :

- Conserver cette séparation entre payload léger et état local résoluble.
- Ajouter `lom_ref` aux événements en P2, à la fin du format `ae`/`ee`.

### Vérifier la capture après pop de navigation

État actuel :

- `didPop` capture `previousRoute`, mais attend l'animation de la route retirée.

Risque :

- Un test widget dédié reste nécessaire pour verrouiller le comportement.

Cible :

- Tester push, pop, replace et nested navigators.
- Ajouter un test widget dédié aux transitions de route.

## Priorité P1 - À traiter avant une V2 stable

Statut : les points P1 ci-dessous ont été traités de manière minimaliste dans le runtime V2. Il n'y a pas de nouvelle API publique ; le cycle de vie reste interne au SDK.

### Revoir le hook global `onBuildScheduled`

État actuel :

- `TreeDetector` remplace `BuildOwner.onBuildScheduled`.
- Le hook précédent est appelé.
- Le hook précédent est restauré lors du dispose interne si le wrapper courant est encore celui du SDK.
- Le SDK ne possède pas de méthode de dispose publique.

Risque :

- Effets de bord dans les scénarios hot restart, tests widget, remount ou désactivation future.

Cible :

- Conserver le cycle de vie interne du detector.
- Documenter que le SDK est conçu pour vivre pendant toute la durée du processus, sans API publique de dispose à ce stade.

### Adapter la règle de cooldown LOM pour la navigation

État actuel :

- Le cooldown de 400 ms s'applique aux mutations UI.
- Les captures venant de la navigation ne sont pas bloquées par ce cooldown.

Risque :

- Une mutation UI juste avant une navigation peut empêcher la capture du nouvel écran.

Cible :

- Conserver la priorité navigation.

### Clarifier la politique de déduplication LOM

État actuel :

- Si une signature existe dans le cache, `LomTreeInspector` retourne un `LomRef`.
- Si une mutation UI produit la même signature que la dernière capture, elle est ignorée.
- Si une navigation produit une signature connue, un `LomRef` est conservé.

Cible :

- Garder la règle par trigger : mutation identique consécutive ignorée, navigation connue envoyée comme `LomRef`.

### Corriger les priorités de `LomTreeConfig`

État actuel :

- `semantics` est évalué avant `noiseAt`.
- `TextFormField` est conservé comme zone sémantique et n'est plus traité comme bruit.

Risque :

- Certains widgets sémantiques peuvent être aplatis alors qu'ils devraient rester comme zones.

Cible :

- Conserver la priorité `pruneAt`, `semantics`, `noiseAt`, `ignoreAt`.
- Tester plus tard `TextField`, `TextFormField`, boutons, images, icônes et gestes custom en widget tests.

### Ajuster la détection double tap

État actuel :

- Le premier tap est enregistré immédiatement pour garder une latence basse.
- Les taps récents sont conservés dans `_lastTaps` pendant `doubleTapTimeout`.
- Plusieurs taps récents peuvent coexister pour supporter le double tap multi-touch.
- Aucun `Timer` n'est utilisé dans `GestureCollector`.
- Dans le chunk, un `doubleTap` est groupé juste après le `tap` compatible quand celui-ci existe encore dans le même chunk.

Risque :

- Un double tap produit `tap + doubleTap`, ce qui doit être interprété comme une série cohérente et non comme deux actions indépendantes.

Cible :

- Conserver la priorité latence : tap immédiat, flush non retardé, double tap détecté comme événement additionnel et ordonné avec son tap d'origine.

### Dédupliquer le dernier point du sampling

État actuel :

- `_samplePositions` ajoute le dernier point seulement s'il n'a pas déjà été conservé.

Risque :

- Trajectoires légèrement bruitées ou points répétés.

Cible :

- Conserver cette déduplication du dernier point.

### Nettoyer les APIs internes no-op

État actuel :

- `NoOpContext.currentRouteElement` retourne `null`.

Risque :

- Une API no-op devrait absorber les appels sans exception.

Cible :

- Ajouter plus tard un test de non-crash avant initialisation si nécessaire.

### Libérer les callbacks et ressources au dispose

État actuel :

- `SessionRecorderWidget.dispose` draine les collectors.
- Le controller nettoie la callback d'interruption.
- Le reporter ferme son client HTTP lors du dispose interne.
- Le detector LOM restaure son hook `onBuildScheduled` si possible.

Cible :

- Conserver cette stratégie interne sans ajouter de `SessionRecorder.dispose()` public.

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
- Scroll avec séquence `scrollStart`, `drag...`, `scrollEnd`.
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

La V2 est proche d'une base publiable, mais elle ne doit pas encore être considérée comme stable sans refaire les validations locales complètes.
Les points P0 et P1 runtime ont été traités de manière minimaliste ; les risques restants sont surtout la couverture widget, les validations de publication et les évolutions P2.
