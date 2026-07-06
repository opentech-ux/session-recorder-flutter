# 030 - Vue d'ensemble des fonctionnalités

## Statut

Draft

## But

Ce document introduit les fonctionnalités actuellement couvertes par le package `SessionRecorder`.
Contrairement à `02_architecture`, cette section décrit ce que le SDK capture et comment chaque capacité se comporte.

## Fonctionnalités actuelles

Le package couvre trois familles de fonctionnalités :

1. Capture comportementale
2. Capture LOM
3. Reporting des données capturées

Le reporting reste documenté dans `02_architecture`, car il fait partie du socle de transport et du runtime plutôt que d'une fonctionnalité métier isolée.

## Capture comportementale

La capture comportementale transforme les signaux Flutter en événements compacts :

- actions (`ae`) : `tap`, `doubleTap`, `longPress` ;
- explorations (`ee`) : `drag`, `pinch`, `scrollStart`, `scrollEnd`.

Voir `031_event-capture-pipeline.md`.

## Capture LOM

La capture LOM produit une représentation spatiale de l'écran actif.

Elle couvre :

- capture après navigation ;
- capture après mutation significative de l'UI ;
- déduplication par signature ;
- production de `Lom` ou `LomRef` ;
- résolution de zones pour les actions.

Voir `032_lom-capture-pipeline.md`.

## Fonctionnalités réservées

Certaines fonctionnalités sont présentes dans le contrat mais non implémentées :

- `pnt` pour les métriques de performance ;
- `lom_ref` à la fin des chaînes d'événements ;
- flush réseau prioritaire lors du lifecycle suspendu.

Ces points sont suivis dans `04_evolution`.

