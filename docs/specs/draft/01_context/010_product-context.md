# 010 - Product Context

## Statut

Draft

## But

Ce document décrit le produit à construire, ses cas d'usage et ses contraintes fonctionnelles, sans détailler l'architecture interne.

## Contexte

Le package `SessionRecorder` est un SDK analytique intégré aux applications Flutter des clients. 
Son objectif est de capturer l'expérience utilisateur de manière totalement transparente.

Pour garantir une capture exhaustive (interactions, structure visuelle et navigation), l'intégration par le client se fait en 3 étapes simples :

- Initialisation : Configuration du endpoint et des paramètres globaux via `SessionRecorder.init()` au démarrage de l'application (dans le main()).
- Enveloppe UI (Wrapper) : Ajout du `SessionRecorderWidget` à la racine de l'application (autour du `MaterialApp`) pour activer l'écoute globale des gestes et du défilement.
- Observation de la navigation : Injection du `SessionNavigatorObserver` dans le routeur (ex: `Navigator` classique ou `GoRouter`) pour déclencher la capture de l'arbre de widgets à chaque transition d'écran.

Exemple d'intégration standard :

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialisation
  SessionRecorder.init(
    SessionRecorderConfig(endpoint: "https://demo-client.ux-key.com/endpoint"),
  );

  runApp(
    // 2. Wrapper UI
    SessionRecorderWidget(
      child: MaterialApp(
        // 3. Observer de navigation
        navigatorObservers: [SessionNavigatorObserver()],
        home: const HomeScreen(),
      ),
    ),
  );
}
```

Une fois chargée, le package :

- capture le comportement utilisateur sur l'application (taps, scrolls, explorations) ;
- capture la structure spatiale de la page sous forme de LOM (Layout Object Model) ;
- envoie les données collectées par lots (chunks) vers un endpoint de stockage ;
- fonctionne de manière invisible et non bloquante pour l'application hôte.

## Privacy by Design (Confidentialité)

Le SDK est conçu pour respecter strictement la vie privée des utilisateurs finaux. Il ne capture aucune donnée sensible ni contenu textuel. Le moteur d'analyse se limite exclusivement à la capture des métadonnées spatiales (tailles et positions des widgets, width, height, x, y) pour reconstruire les interactions, garantissant ainsi l'absence de fuite de PII (Personally Identifiable Information).

Dans le payload réseau final, un nœud `Root` n'expose que son identifiant de zone (`id`, ex: `z12`), sa boîte géométrique (`b`: x, y, width, height) et ses enfants (`c`). Les informations internes utilisées pour l'analyse ou le debug (`objectId`, `widgetType`, `renderType`) ne sont pas sérialisées dans le payload envoyé au backend.

## Cible V2

La V2 de ce package Dart doit préserver la simplicité d’installation actuelle, tout en reposant sur une architecture plus propre, modulaire et hautement performante.

Les objectifs produit sont :

- conserver les capacités de capture de base de la V1 (sessions, comportements, LOMs, performances) ;
- minimiser le poids de la bibliothèque chargée côté client ;
- limiter l’impact système avec des seuils stricts (ex: overhead CPU < 5%, consommation mémoire additionnelle < 15MB) ;
- concevoir une architecture modulaire permettant d’activer ou de désactiver des plugins (fonctionnalités spécifiques) à la demande ;
- proposer une base Dart claire, testable et maintenable pour les itérations futures.

## Contraintes fortes

- le package ne doit en aucun cas perturber, bloquer ou ralentir le Thread UI de l'application du client ;
- le package ne doit pas dépendre de bibliothèques runtime externes lourdes (à l'exception d'outils basiques comme UUID) ;
- les fonctionnalités non essentielles ne doivent pas alourdir le bundle standard ;

- Résilience réseau : en cas de perte de connexion, le SDK doit gérer l'échec silencieusement (ex: rejet des données) sans provoquer de fuite de mémoire ou de crash.

## Fonctionnel attendu

Le produit doit permettre :

- la création et le suivi d'une session utilisateur unique ;
- la capture d'événements d'action (taps, double taps, long presses) ;
- la capture d'événements d'exploration (drags, pinches, scrolls) ;
- la capture de snapshots LOM à chaque changement d'état significatif ou transition de route ;
- la capture d'indicateurs de performance de l'appareil (champ `pnt` réservé, non implémenté à ce stade) ;
- le drainage des gestes et scrolls en cours lors des interruptions ou transitions de lifecycle, sans flush réseau prioritaire garanti à ce stade ;
- l'envoi périodique et asynchrone des données accumulées (par défaut, toutes les 10 secondes).
