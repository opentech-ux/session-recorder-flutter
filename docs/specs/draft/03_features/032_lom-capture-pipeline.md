# 032 - Pipeline de capture LOM

## Statut

Draft

## But

Ce document décrit comment le SDK capture le LOM, comment il déduplique les snapshots et comment il résout les zones touchées.

## Vue d'ensemble

```text
Navigation ou mutation UI
  -> TreeDetector.captureTree
  -> LomTreeInspector.captureLom
  -> LomTreeHasher.signatureRoots
  -> Lom ou LomRef
  -> ContextImpl.recordLom
```

## Déclencheurs de capture

Deux familles de déclencheurs existent.

Navigation :

- `SessionNavigatorObserver` observe `didPush`, `didPop` et `didReplace`.
- Il marque le contexte comme en navigation.
- Il interrompt les collectors pour drainer les événements en cours.
- Il attend que l'animation de route soit terminée ou dismiss.
- Il capture après la prochaine frame avec `addPostFrameCallback`.

Mutation UI :

- `TreeDetector` remplace `BuildOwner.onBuildScheduled` par un wrapper.
- Chaque build schedule relance un debounce.
- Après le debounce, il capture le LOM si l'application n'est pas en navigation.
- Lors du dispose interne, le debounce est annulé et le hook précédent est restauré si le wrapper courant est encore celui du SDK.

Constantes actuelles :

- debounce : 300 ms ;
- cooldown entre captures : 400 ms pour les mutations UI.

Règle :

- les captures de navigation ne sont pas bloquées par le cooldown ;
- les mutations UI identiques consécutives sont ignorées pour réduire le bruit.

## Sélection de l'élément racine

`TreeDetector` capture depuis l'élément courant de route.

Priorité :

1. `currentRouteElement`, défini par `SessionNavigatorObserver`.
2. Fallback brute-force : recherche d'un `Navigator` depuis `WidgetsBinding.instance.rootElement`.

Si aucun élément n'est disponible, la capture est ignorée et un warning est loggé.

## LomTreeInspector

`LomTreeInspector` transforme un arbre Flutter en arbre `Root`.

Étapes :

1. Vérifier que l'élément est non nul et monté.
2. Visiter récursivement les enfants.
3. Filtrer les widgets selon `LomTreeConfig`.
4. Extraire les rectangles globaux via `MathUtils.transformRect`.
5. Construire un `Root` avec id, objectId, widgetType, renderType, box et children.
6. Calculer la signature spatiale.
7. Retourner soit un `Lom`, soit un `LomRef`, soit `null`.

## LomTreeConfig

`LomTreeConfig` contrôle la granularité de l'arbre capturé.

Catégories :

- `pruneAt` : stoppe la visite sous certains widgets.
- `ignoreAt` : ignore certains widgets et continue avec leurs enfants.
- `noiseAt` : flatten des widgets de layout ou de décoration.
- `semantics` : conserve certains widgets importants même s'ils ne sont pas des `RenderObjectWidget` typiques.

Priorité :

1. `pruneAt`
2. `semantics`
3. `noiseAt`
4. `ignoreAt`

Objectif :

- réduire le bruit ;
- éviter de capturer des détails non utiles ;
- conserver les zones interactives ou visuellement significatives.

## Hash et déduplication

`LomTreeHasher` calcule une signature spatiale à partir de :

- type de widget ;
- position globale ;
- taille ;
- ordre de parcours ;
- hiérarchie.

La géométrie est bucketisée avec une tolérance de 4 px pour éviter les changements dus aux micro-mouvements.

Comportement actuel de `LomTreeInspector` :

- Si la signature est identique à la dernière et vient d'une mutation UI, aucun LOM n'est retourné.
- Si la signature est connue et vient d'une navigation, un `LomRef` est retourné.
- Si la signature est connue mais non consécutive, un `LomRef` peut être retourné.
- Sinon, un nouveau `Lom` est créé avec un UUID v7 et stocké dans le cache.
- Le contexte conserve localement les arbres complets connus pour continuer à résoudre les zones même lorsqu'un `LomRef` léger est envoyé.
- Le cache de signatures est un LRU large et léger (`signature -> lomId`) afin de conserver la déduplication même si l'utilisateur revient beaucoup plus tard sur un écran connu.
- Le cache de roots est un LRU plus petit (`lomId -> Root`) parce qu'il garde des arbres complets uniquement pour la résolution locale de `zone`.

Note d'implémentation :

- `_lastSignature` est mis à jour aussi lors d'un `LomRef`, afin que le build identique suivant ne génère pas de bruit.

## Payload Root

`Root` contient en mémoire :

- `id`
- `objectId`
- `widgetType`
- `renderType`
- `box`
- `children`

Le payload réseau `toMap()` expose uniquement :

- `id` sous forme `z{id}` ;
- `b` pour la box `[x, y, width, height]` ;
- `c` pour les enfants.

Les champs internes ne sont pas envoyés au backend.

## TapTreeFinder

`TapTreeFinder` résout une position pointeur vers la zone `Root` la plus pertinente.

Mécanisme :

1. Exécuter un hit-test Flutter via `RendererBinding.instance.hitTestInView`.
2. Récupérer les `RenderBox` touchés et leurs hash codes.
3. Comparer ces hash codes aux `objectId` des `Root`.
4. Retourner le `Root` le plus profond dans le chemin de hit-test.
5. Si le hit-test ne permet pas de trouver un `objectId`, utiliser les bounds du LOM courant comme fallback géométrique.

Cette résolution est utilisée par `GestureCollector` pour remplir `zone` dans les actions.

## Overlay debug

`LomTreeOverlay` est activé avec `SessionRecorderConfig.debugShowTree`.

Règles :

- Il ne peint qu'en debug.
- Il écoute le `ValueNotifier<LomAbstract?>` du `TreeDetector`.
- Il dessine les rectangles `Root` au-dessus de l'application.
- Il ignore les pointeurs pour ne pas perturber l'application cliente.

## Limites actuelles

- Le fallback brute-force existe, mais l'architecture attend que le client fournisse un `SessionNavigatorObserver`.
