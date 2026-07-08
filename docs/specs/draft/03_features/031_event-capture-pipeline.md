# 031 - Pipeline de capture des événements

## Statut

Draft

## But

Ce document décrit comment le SDK capture les événements utilisateur avant de les ajouter au chunk courant.

## Point d'entrée

`SessionRecorderWidget` installe deux mécanismes Flutter :

- `Listener` pour les événements pointeur bas niveau ;
- `NotificationListener<ScrollNotification>` pour les scrolls.

```text
SessionRecorderWidget
  -> Listener.onPointerDown/Move/Up/Cancel
    -> GestureCollector
      -> ActionEvent / ExplorationEvent
      -> ContextImpl.recordAction / recordExploration

SessionRecorderWidget
  -> NotificationListener<ScrollNotification>
    -> ScrollCollector
      -> ScrollExplorationEvent
      -> ContextImpl.recordExploration
```

## GestureCollector

`GestureCollector` détecte les gestes construits à partir des événements pointeur.

Gestes pris en charge :

- `tap`
- `doubleTap`
- `longPress`
- `drag`
- `pinch`

État interne :

- `_pointers` : traces actives par identifiant de pointeur.
- `_lastTaps` : historique court des taps récents pour détecter les double taps, y compris multi-touch.
- `_pinchMetrics` : baseline géométrique pour évaluer un pinch.

Règle de performance :

- le collector de gestes n'utilise pas de `Timer` ;
- les actions et explorations sont évaluées à partir des événements pointeur et des drains explicites.

## PointerTrace et TimedPosition

`PointerTrace` représente un pointeur actif ou terminé.

Il contient :

- l'identifiant pointeur ;
- le type de geste courant ;
- une liste de `TimedPosition` ;
- un flag `isOrphanedPointer` utilisé lors des transitions de pinch.

`TimedPosition` capture :

- timestamp absolu ;
- position pointeur ;
- viewport résolu au moment du point.

## Détection des actions

Une action est une interaction ponctuelle.

Flux simplifié :

```text
PointerDown -> création PointerTrace(type tap)
PointerMove -> update distance/duration/type
PointerUp
  -> longPress si durée >= timeout et distance faible
  -> drag si distance >= touchSlop
  -> doubleTap si un tap récent proche existe dans l'historique
  -> tap sinon
```

Les actions créent :

- `TapActionEvent`
- `DoubleTapActionEvent`
- `LongPressActionEvent`

La `zone` est résolue via `ContextImpl.findRoot(position)`.
Si aucune zone n'est trouvée, la valeur de repli est `z0`.

Règle double tap :

- chaque tap est enregistré immédiatement pour garder une latence basse et ne pas retarder le flush réseau ;
- les taps récents restent dans `_lastTaps` pendant `doubleTapTimeout` pour détecter un éventuel `doubleTap` ;
- si un second tap valide arrive près d'un tap récent, un `DoubleTapActionEvent` est émis en plus du tap déjà enregistré ;
- plusieurs taps récents peuvent coexister pour supporter le double tap avec deux doigts ou plus ;
- dans le chunk, un `doubleTap` est inséré juste après le `tap` compatible qui l'a déclenché lorsque ce tap existe encore dans le chunk.
- si le `tap` d'origine a déjà été envoyé dans un chunk précédent, le `doubleTap` reste dans le chunk courant ; le flush réseau n'est pas retardé.

## Détection des explorations

Une exploration est un comportement continu.

Types actuels :

- `DragExplorationEvent`
- `PinchExplorationEvent`
- `ScrollExplorationEvent`

Pour les drags et pinches, le collector applique un sampling temporel :

- 1 point toutes les 50 ms ;
- le premier et le dernier point sont conservés ;
- le dernier point n'est pas ajouté deux fois s'il a déjà été conservé par le seuil temporel.

## Transitions de gestes

Le collector gère plusieurs transitions :

- `longPress` peut être émis puis transformé en `drag` si le pointeur se déplace.
- `drag` peut être émis puis transformé en `pinch` si plusieurs pointeurs forment un zoom.
- Lorsqu'un pinch se termine et qu'un pointeur reste actif, ce pointeur peut être converti en pointeur orphelin pour éviter un faux tap.
- Lors d'un drain forcé, un `longPress` immobile déjà qualifié est émis avant de nettoyer le pointeur.

Ces transitions permettent de conserver les segments significatifs sans attendre la fin complète de tous les pointeurs.

## ScrollCollector

`ScrollCollector` écoute les `ScrollNotification`.

Règles actuelles :

- `OverscrollNotification` est ignoré.
- Les notifications qui ne sont pas `ScrollStartNotification`, `ScrollUpdateNotification` ou `ScrollEndNotification` n'actualisent pas le viewport de scroll.
- `ScrollStartNotification` crée un `ScrollExplorationEvent` phase start.
- `ScrollUpdateNotification` met à jour le viewport actif mais ne crée pas d'événement.
- `ScrollEndNotification` crée un `ScrollExplorationEvent` phase end.
- `forceRecordCollector` force un scroll end si un scroll est encore actif.

Interprétation payload :

- pendant un scroll tactile, les points `drag` émis par le `Listener` sont conservés ;
- la séquence `scrollStart`, `drag...`, `scrollEnd` représente une seule exploration de scroll côté backend ;
- un `drag` hors séquence scroll reste une exploration autonome ;
- aucun `scrollUpdate` n'est ajouté au payload actuel.

## Viewport de scroll

Le scroll collector calcule deux rectangles :

- `scrollPhysicalBounds` : zone visible physique du scrollable.
- `scrollVirtualCanvas` : surface virtuelle du contenu scrollable, ajustée avec `scrollMetrics.pixels`.

Ces rectangles sont stockés dans `ContextImpl`.
Ensuite, les gestes pointeur utilisent `resolveViewport(position)` pour savoir si la position appartient au viewport écran ou au viewport virtuel de scroll.
Après `ScrollEndNotification` ou un drain forcé, le viewport de scroll est remis à zéro pour éviter qu'une géométrie ancienne soit réutilisée.

## Drain des collectors

Les collectors peuvent être forcés à enregistrer leur état courant.

Déclencheurs actuels :

- interruption de navigation via `SessionNavigatorObserver` ;
- lifecycle suspendu via `SessionLifecycleObserver` ;
- dispose de `SessionRecorderWidget`.

Ce drain ajoute les événements manquants au chunk courant, mais ne force pas un envoi réseau immédiat.

## Limites actuelles

- Les événements n'incluent pas encore `lom_ref`.
- Les scroll updates ne sont pas sérialisés comme événements séparés.
- Les événements d'exploration ne portent pas de `zone`.
- Les performances (`pnt`) ne sont pas capturées.
