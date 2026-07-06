# 022 - Vue d'ensemble de l'architecture

## Statut

Draft

## But

Ce document donne une vue d'ensemble de l'architecture actuelle du package `SessionRecorder`.
Il complète les fondations et la structure du projet avant d'entrer dans les APIs et le runtime.

## Principes généraux

L'architecture actuelle est organisée autour d'un SDK Flutter embarqué dans l'application cliente.
Le package doit rester invisible pour l'utilisateur final et ne doit jamais bloquer le thread UI.

Les responsabilités sont séparées en cinq zones principales :

1. API publique et intégration client
2. API interne et runtime de session
3. Fonctionnalités de capture
4. Reporting réseau, lifecycle et inactivité
5. Modèles sérialisables et contrats de payload

## Vue de flux

```text
Application cliente
  -> SessionRecorder.init(config)
  -> SessionRecorderEngine
  -> ContextImpl + ControllerImpl

SessionRecorderWidget
  -> Collectors de fonctionnalités
  -> ContextImpl.recordAction / recordExploration
  -> Chunk courant

SessionNavigatorObserver
  -> route stabilisée
  -> capture LOM
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
- Les fonctionnalités produisent des records, mais ne possèdent pas le chunk courant.
- Les modèles restent sans dépendance forte vers le core ; ils sérialisent leur propre représentation.

## Frontières importantes

- Frontière publique : `SessionRecorder`, `SessionRecorderConfig`, `SessionRecorderWidget`, `SessionNavigatorObserver`.
- Frontière interne : `SessionRecorderEngineInternal`, `SessionRecorderContext`, `SessionRecorderController`.
- Frontière de capture : `SessionRecorderWidget` et `SessionNavigatorObserver` sont les points d'entrée runtime.
- Frontière de stockage mémoire : `ContextImpl` est le seul propriétaire du chunk courant.
- Frontière réseau : le backend reçoit uniquement des `Chunk`, jamais des événements unitaires en temps réel.
- Frontière privacy : le payload final ne contient pas de texte, de valeur utilisateur ni de type de widget interne pour les `Root`.

## Découpage documentaire

Dans `02_architecture` :

- `020_foundation-and-guidelines.md` : fondations et lignes directrices du package ;
- `021_project-structure.md` : structure du projet Flutter ;
- `022_architecture-overview.md` : carte d'ensemble du runtime ;
- `023_public-api-and-integration.md` : API publique et intégration client ;
- `024_runtime-core.md` : API interne, moteur, contexte et controller ;
- `025_reporting-lifecycle-network.md` : chunks, timer, réseau, lifecycle et inactivité.

Dans `03_features` :

- captures comportementales ;
- capture LOM ;
- futures fonctionnalités optionnelles.

Dans `04_evolution` :

- évolutions prévues ;
- écarts connus ;
- sujets à supprimer quand ils seront implémentés.

