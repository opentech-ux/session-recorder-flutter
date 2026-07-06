# 021 - Structure du projet

## Statut

Draft

## But

Ce document décrit la structure actuelle du projet Flutter et le rôle des principaux dossiers.

## Structure de haut niveau

```text
lib/
  session_recorder.dart
  src/
    collectors/
    constants/
    controllers/
    core/
    enums/
    models/
    observers/
    session/
    tree/
    utils/

test/
  session_record_ux_test.dart

docs/
  specs/
    draft/
      01_context/
      02_architecture/
      03_features/
      04_evolution/
```

## lib/session_recorder.dart

Point d'entrée public du package.

Il exporte uniquement :

- `SessionRecorder`
- `SessionRecorderConfig`
- `SessionRecorderWidget`
- `SessionNavigatorObserver`

Règle :

- aucune API interne de `lib/src/` ne doit être exportée sans décision explicite.

## lib/src/session

Contient les éléments proches de l'intégration SDK :

- façade publique `SessionRecorder` ;
- configuration `SessionRecorderConfig` ;
- widget racine `SessionRecorderWidget` ;
- modèle `Session` ;
- logger interne `SessionLogger`.

Ce dossier représente la couche d'entrée du SDK.

## lib/src/core

Contient le runtime interne :

- moteur `SessionRecorderEngine` ;
- contexte `SessionRecorderContext` ;
- controller `SessionRecorderController` ;
- reporter `SessionRecorderReporter`.

Ce dossier porte l'orchestration, l'état mutable et le cycle de reporting.

## lib/src/collectors

Contient les collectors comportementaux :

- `GestureCollector`
- `ScrollCollector`

Ces composants transforment les signaux Flutter bas niveau en records métier.
Ils ne doivent pas envoyer directement de données réseau.

## lib/src/observers

Contient les observers Flutter :

- `SessionNavigatorObserver`
- `SessionLifecycleObserver`

Ils connectent le SDK à la navigation et au lifecycle de l'application.

## lib/src/tree

Contient la capture et l'analyse LOM :

- `TreeDetector`
- `LomTreeInspector`
- `LomTreeHasher`
- `LomTreeConfig`
- `TapTreeFinder`
- `LomTreeOverlay`

Ce dossier est responsable de la représentation spatiale de l'interface.

## lib/src/models

Contient les modèles sérialisables et les objets runtime :

- `Chunk`
- `ActionEvent`
- `ExplorationEvent`
- `Lom` / `LomRef`
- `Root`
- `PointerTrace`
- modèles liés au pinch et au scroll.

Ces modèles décrivent les données qui entrent dans le chunk ou qui aident à les produire.

## lib/src/controllers

Contient les contrôleurs transverses.

Actuellement :

- `InactivityDetector`

Ce dossier peut accueillir d'autres contrôleurs non liés directement à une UI ou à un modèle de payload.

## lib/src/constants, enums et utils

Responsabilités :

- `constants/` : seuils de gestes, version de librairie, type de librairie ;
- `enums/` : types de gestes, phases de scroll, types de navigation ;
- `utils/` : fonctions mathématiques et géométriques.

## test

Le dossier `test/` existe mais la couverture est actuellement minimale.

Les tests à ajouter en priorité sont listés dans `04_evolution`.

