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

Constantes actuelles :

- debounce : 300 ms ;
- cooldown entre captures : 400 ms.

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

- Si la signature existe déjà dans le cache, un `LomRef` est retourné.
- Sinon, un nouveau `Lom` est créé avec un UUID v7.
- La signature et l'id du LOM sont stockés dans le cache.

Note d'implémentation :

- Le code contient aussi une vérification `_lastSignature`, mais le cache est consulté avant. En pratique, une signature déjà connue retourne un `LomRef`.

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

Cette résolution est utilisée par `GestureCollector` pour remplir `zone` dans les actions.

## Overlay debug

`LomTreeOverlay` est activé avec `SessionRecorderConfig.debugShowTree`.

Règles :

- Il ne peint qu'en debug.
- Il écoute le `ValueNotifier<LomAbstract?>` du `TreeDetector`.
- Il dessine les rectangles `Root` au-dessus de l'application.
- Il ignore les pointeurs pour ne pas perturber l'application cliente.

## Limites actuelles

- Si le LOM courant est un `LomRef` sans `root`, `TapTreeFinder` ne peut pas résoudre la zone et les actions retombent à `z0`.
- Le fallback brute-force existe, mais l'architecture attend que le client fournisse un `SessionNavigatorObserver`.
- La déduplication actuelle est cache-first : les signatures connues produisent un `LomRef`.

