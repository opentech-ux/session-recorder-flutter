# 020 - Vue d'ensemble de l'architecture

## Statut

Draft

## But

Ce document donne une vue d'ensemble de l'architecture actuelle du package `SessionRecorder`.
Il sert de carte de lecture avant d'entrer dans les documents plus détaillés de la section `02_architecture`.

## Principes généraux

L'architecture actuelle est organisée autour d'un SDK Flutter embarqué dans l'application cliente.
Le package doit rester invisible pour l'utilisateur final et ne doit jamais bloquer le thread UI.

Les responsabilités sont séparées en six zones principales :

1. API publique et intégration client
2. Core runtime et état de session
3. Capture des événements utilisateur
4. Capture LOM et résolution spatiale
5. Reporting réseau, lifecycle et inactivité
6. Modèles sérialisables et contrats de payload

## Carte des modules

```text
lib/session_recorder.dart
  -> Expose uniquement l'API publique du package.

lib/src/session/
  -> Façade publique, configuration, widget racine, session et logs.

lib/src/core/
  -> Moteur interne, contexte runtime, controller et reporter réseau.

lib/src/collectors/
  -> Capture des gestes pointeur et des notifications de scroll.

lib/src/observers/
  -> Observation de navigation Flutter et lifecycle applicatif.

lib/src/tree/
  -> Capture, filtrage, hash, overlay debug et résolution du LOM.

lib/src/models/
  -> Entités runtime et objets sérialisés dans les chunks.

lib/src/controllers/
  -> Contrôleurs transverses, actuellement l'inactivité.

lib/src/constants/ et lib/src/enums/
  -> Valeurs de seuils, versions et types d'événements.
```

## Vue de flux

```text
Application cliente
  -> SessionRecorder.init(config)
  -> SessionRecorderEngine
  -> ContextImpl + ControllerImpl

SessionRecorderWidget
  -> Listener / NotificationListener
  -> GestureCollector / ScrollCollector
  -> ContextImpl.recordAction / recordExploration
  -> Chunk courant

SessionNavigatorObserver
  -> route stabilisée
  -> TreeDetector.captureTree(true)
  -> LomTreeInspector.captureLom
  -> ContextImpl.recordLom
  -> Chunk courant

SessionRecorderReporter
  -> timer 10s
  -> ContextImpl.extractChunk
  -> HTTP POST endpoint
```

## Direction des dépendances

- L'application cliente ne dépend que de l'API publique exposée par `lib/session_recorder.dart`.
- Les collectors et observers communiquent avec le runtime via `SessionRecorder.engine`, marqué comme API interne.
- Le `SessionRecorderEngine` possède le `ContextImpl` et le `ControllerImpl`.
- Le `ContextImpl` possède l'état mutable de session : session courante, chunk courant, LOM courant, route active et viewports.
- Le `ControllerImpl` orchestre le reporting, l'inactivité, les observers de navigation et les interruptions de collectors.
- Les modèles restent sans dépendance forte vers le core ; ils sérialisent leur propre représentation.

## Frontières importantes

- Frontière publique : `SessionRecorder`, `SessionRecorderConfig`, `SessionRecorderWidget`, `SessionNavigatorObserver`.
- Frontière de capture : `SessionRecorderWidget` et `SessionNavigatorObserver` sont les points d'entrée runtime.
- Frontière de stockage mémoire : `ContextImpl` est le seul propriétaire du chunk courant.
- Frontière réseau : le backend reçoit uniquement des `Chunk`, jamais des événements unitaires en temps réel.
- Frontière privacy : le payload final ne contient pas de texte, de valeur utilisateur ni de type de widget interne pour les `Root`.

## Documents de cette section

- `021_public-api-and-integration.md` : API publique, configuration et intégration client.
- `022_runtime-core.md` : moteur interne, contexte, controller et état mutable.
- `023_event-capture-pipeline.md` : gestes, scrolls, sampling et drain des collectors.
- `024_lom-capture-pipeline.md` : navigation, mutations UI, capture LOM, hash et zones.
- `025_reporting-lifecycle-network.md` : chunks, timer, réseau, lifecycle et inactivité.
- `026_architecture-evolution-notes.md` : points d'évolution et écarts connus.
