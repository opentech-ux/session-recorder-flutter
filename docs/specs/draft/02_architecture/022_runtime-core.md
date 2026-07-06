# 022 - Runtime Core

## Statut

Draft

## But

Ce document décrit les composants internes qui maintiennent l'état runtime du SDK.

## Vue d'ensemble

Le core runtime est constitué de quatre pièces principales :

- `SessionRecorderEngineInternal`
- `SessionRecorderEngine` / `NoOpSessionRecorderEngine`
- `SessionRecorderContext`
- `SessionRecorderController`

```text
SessionRecorder.init(config)
  -> SessionRecorderEngine(config)
    -> ContextImpl(engine)
    -> ControllerImpl(engine)
    -> start()
      -> context.start()
      -> controller.startReporting()
```

## SessionRecorderEngineInternal

`SessionRecorderEngineInternal` est le contrat interne partagé par le moteur réel et le moteur no-op.

Il expose :

- `start()`
- `isEnabled`
- `config`
- `context`
- `controller`

Ce contrat permet aux collectors et observers d'appeler le SDK sans connaître le type concret du moteur.

## NoOpSessionRecorderEngine

`NoOpSessionRecorderEngine` est le fallback de sécurité.

Responsabilités :

- absorber les appels quand le SDK n'est pas initialisé ;
- éviter les crashes si un collector ou observer est créé trop tôt ;
- fournir un `NoOpContext` et un `NoOpController`.

Règle :

- Toute API interne appelée avant `SessionRecorder.init` doit rester sans effet observable.

## SessionRecorderEngine

`SessionRecorderEngine` est le moteur réel du SDK.

Responsabilités :

- conserver la configuration ;
- créer le `ContextImpl` ;
- créer le `ControllerImpl` ;
- démarrer la détection LOM via le contexte ;
- démarrer le reporting via le controller.

Le moteur ne stocke pas directement les événements ou les LOMs : cette responsabilité appartient au contexte.

## SessionRecorderContext

`SessionRecorderContext` est le contrat de stockage et de résolution spatiale.

Responsabilités principales :

- démarrer le `TreeDetector` ;
- conserver la session courante ;
- conserver le chunk courant ;
- conserver le LOM courant ;
- conserver l'élément de route actif ;
- stocker les viewports écran/scroll ;
- enregistrer actions, explorations et LOMs ;
- extraire un chunk prêt à envoyer.

## ContextImpl

`ContextImpl` est le propriétaire de l'état mutable de session.

État interne :

- `_currentSession`
- `_currentChunk`
- `_currentLom`
- `_currentRouteElement`
- `_screenViewport`
- `_scrollPhysicalBounds`
- `_scrollVirtualCanvas`
- `_detector`

Règles :

- Une session est créée à la construction du contexte.
- Le chunk courant reçoit le `sid` de cette session.
- `recordAction` ajoute l'action au chunk puis ping l'inactivité.
- `recordExploration` ajoute l'exploration au chunk puis ping l'inactivité.
- `recordLom` met à jour le LOM courant puis ajoute le LOM au chunk.
- `extractChunk` retourne `null` si le chunk est vide.
- Si le chunk n'est pas vide, `extractChunk` le ferme, crée un nouveau chunk et conserve le même `sid`.

## Résolution spatiale

Le contexte expose deux mécanismes spatiaux :

- `resolveViewport(position)` : retourne le viewport de scroll virtuel si le pointeur est dans la zone scrollable active, sinon le viewport écran.
- `findRoot(position)` : résout la zone touchée dans le LOM courant via `TapTreeFinder`.

Point important :

- La résolution de `zone` dépend du LOM courant et de son arbre `Root`. Si le LOM courant ne contient pas de `root`, la zone retombe à `z0` côté collector.

## SessionRecorderController

`SessionRecorderController` orchestre les sous-systèmes transverses.

Responsabilités :

- enregistrer les `SessionNavigatorObserver` ;
- indiquer si au moins un observer est attaché à un `Navigator` ;
- démarrer/arrêter le reporter ;
- démarrer/arrêter l'inactivité ;
- ping l'inactivité lors des interactions ;
- propager les interruptions aux collectors.

## ControllerImpl

`ControllerImpl` possède :

- la liste des observers de navigation ;
- un `SessionRecorderReporter` ;
- un `InactivityDetector` ;
- une callback `_onCollectorInterrupt`.

Règles :

- `registerObserver` nettoie les observers détachés avant d'ajouter le nouveau.
- `startReporting` démarre le reporter et le timer d'inactivité.
- `stopReporting` arrête le reporter et le timer d'inactivité.
- `interrupt` appelle la callback fournie par `SessionRecorderWidget` pour drainer les collectors.

## InactivityDetector

`InactivityDetector` gère l'arrêt du reporting après inactivité.

Règles actuelles :

- L'intervalle d'inactivité est de 30 secondes.
- Chaque action ou exploration appelle `pingInactivity`.
- À expiration, le controller arrête le reporting.
- Le prochain ping repasse l'état en actif et relance le reporting.
- Les captures LOM seules ne ping pas l'inactivité.

