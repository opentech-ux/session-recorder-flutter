# 020 - Fondations et lignes directrices

## Statut

Draft

## But

Ce document définit les fondations attendues du package Flutter `SessionRecorder`.
Il décrit le socle architectural avant de détailler les APIs, le runtime interne et les fonctionnalités.

## Positionnement

`SessionRecorder` est un package Flutter embarqué dans les applications clientes.
Il doit être installé comme une dépendance applicative classique, puis activé par une configuration minimale au démarrage de l'application.

Le package n'est pas une application autonome.
Il n'impose pas de navigation, de thème, de state management ou de backend local à l'application cliente.

## Lignes directrices

Le package doit rester :

- léger à installer ;
- léger à exécuter ;
- simple à maintenir ;
- sûr pour les applications clients.

## Léger à installer

L'intégration doit rester courte et lisible.

Règles :

- exposer une surface publique minimale ;
- éviter les dépendances runtime lourdes ;
- conserver une configuration explicite et stable ;
- ne pas demander au client de modifier profondément son architecture Flutter ;
- permettre une intégration standard autour de `MaterialApp`, `CupertinoApp` ou `MaterialApp.router`.

## Léger à exécuter

Le SDK doit capturer sans bloquer l'application hôte.

Règles :

- ne pas exécuter de travail lourd directement dans les callbacks fréquents ;
- limiter les captures LOM avec debounce, cooldown et déduplication ;
- échantillonner les événements continus ;
- envoyer les données par chunks plutôt qu'en flux temps réel ;
- accepter la perte silencieuse de données en cas d'échec réseau plutôt que perturber l'application cliente.

## Simple à maintenir

Le code doit rester lisible par responsabilité.

Règles :

- garder une séparation claire entre API publique, core runtime, collectors, tree/LOM, modèles et reporting ;
- garder `ContextImpl` comme propriétaire de l'état mutable de session ;
- éviter les dépendances circulaires entre collectors, reporter et tree ;
- documenter tout changement de payload dans les specs ;
- préférer des modèles compacts et testables.


## Sûr pour les applications clients

Le SDK doit être privacy-first et non intrusif.

Règles :

- ne jamais capturer de texte utilisateur, valeur de champ, label sensible ou contenu métier ;
- ne sérialiser que des métadonnées spatiales dans le payload final ;
- ne pas casser la navigation, le hit-test ou le rendu de l'application hôte ;
- ne pas lancer d'exception non interceptée depuis les couches réseau ou capture ;
- offrir un mode no-op lorsque l'initialisation échoue ou n'a pas encore eu lieu.

## Hiérarchie documentaire

La documentation du projet est organisée par niveau :

- `01_context` : contexte produit et modèle de domaine ;
- `02_architecture` : fondations, structure du projet, API publique, runtime interne et reporting ;
- `03_features` : fonctionnalités capturées par le SDK ;
- `04_evolution` : évolutions prévues, temporaires ou non encore implémentées.

