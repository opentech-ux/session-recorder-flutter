# 011 - Domain Model

## Statut

Draft

## But

Ce document définit les entités et objets métier manipulés par le package `SessionRecorder` (indépendamment du framework), ainsi que leur représentation dans le payload final envoyé au backend.

## Définitions

### Session

Une session représente une période d'activité continue d’un utilisateur sur l'application.
Elle est identifiée par un `sid` (Session ID) et regroupe l'intégralité des données collectées :

- les événements comportementaux : Action Events (ae) et Exploration Events (ee) ;
- les snapshots visuels : LOMs (loms) ;
- les métriques de performance (pnt) ;
- les métadonnées globales du payload : timestamp de la session (ts) et version de la librairie (lib_v).

Règles :

- le `sid` est un UUID v7 (garantissant un tri chronologique naturel) ;
- le `sid` reste identique pendant toute la durée de vie du processus de l'application ;
- la session est considérée comme terminée lorsque l'application est fermée (kill) ou après une période d'inactivité prolongée en arrière-plan.

### Chunk

Un chunk est l'unité d'envoi réseau (le lot de données) de la session.

Règles :

- un chunk regroupe les records capturés sur une fenêtre de temps glissante ;
- la fenêtre temporelle par défaut est de 10 secondes ;
- une session est composée de `1..n` chunks (`10` chunks envoyés lors d'une même visite appartiennent à 1 seule session) ;
- un chunk vide ne doit jamais être envoyé ;
- un chunk contient un timestamp absolu `ts` correspondant au moment de sa création ;
- un chunk embarque la version de la librairie (`lib_v`, ex: `2.0.0`) pour permettre la compatibilité et le versioning des schémas côté backend.

### Record

Un record est l'unité minimale d'information capturée en mémoire avant d'être affectée à un chunk.

Il existe quatre types de records :

1. Événement d'action (Action Event)
2. Événement d'exploration (Exploration Event)
3. Snapshot d'interface (LOM)
4. Mesure de performance (Performance Metric)

### Action Event (ae)

Un action event représente une interaction intentionnelle et ponctuelle de l'utilisateur.

Exemples : `tap`, `doubleTap`, `longPress`.

Représentation (Optimisée pour le réseau) :

- Stocké sous forme compacte (chaîne de caractères sérialisée) pour minimiser le payload.
- Format cible : `timestamp_absolu:event_type:scroll_x,scroll_y:position_x,position_y:lom_ref`
- Exemple : `1775810346601:tap:0,0:788,431:70bde03ac7705f7077`

### Exploration Event (ee)

Un exploration event représente un comportement continu, de navigation ou de lecture.

Exemples : `drag`, `pinch`, `scrollStart`, `scrollEnd`

Représentation :

- `drag` : `timestamp_absolu:event_type:scroll_x,scroll_y:position_x,position_y:lom_ref`
  - example : `1775810346601:drag:0:0,0:123,425:70bde03ac7705f7077`
- `pinch` : `start_timestamp_absolu:event_type:pointer:scroll_x,scroll_y:x1,y1|x2,y2|x3,y3|xn,yn:end_timestamp_absolu:lom_ref`
  - example : `1775810346601:pinch:1:0,0:207,583|207,583|207,583:1775810346750:70bde03ac7705f7077`
- `scrollStart` : `timestamp_absolu:event_type:phase:scroll_x,scroll_y:scroll_width:scroll_height:lom_ref`
  - example `1773931064746:scroll:start:0,0,260,500`
- `scrollEnd` : `timestamp_absolu:event_type:phase:scroll_x,scroll_y:scroll_width:scroll_height:lom_ref`
  - example `1773931065769:scroll:end:-400,0,260,500:70bde03ac7705f7077`

***Note : La fréquence de ces événements étant très élevée (notamment lors du défilement ou du glissement), un mécanisme d'échantillonnage (sampling / throttling) est appliqué en amont (ex: 1 point tous les 50ms).***

### LOM Snapshot (loms)

Un LOM (Layout Object Model) snapshot est une représentation structurée et hiérarchique de l'arbre des vues (Widget Tree / View Tree) à un instant.

Caractéristiques :

- Identifié par un `id` unique et un `signature` (hash de la structure spatiale) ;
- Contient les dimensions de l'écran (`w`, `h`), le timestamp (`ts`), et un arbre récursif (`r`) de nœuds (`Root`).

Déclencheurs (Triggers) de capture :

Un snapshot est généré dans deux cas précis :

1. Navigation : Immédiatement après la fin d'une animation de transition de route (écran stabilisé).
2. Mutation de l'UI : Lorsqu'un changement d'état significatif est détecté sur l'écran actif (via `onBuildScheduled` ou équivalent), après un délai de debounce (ex: 300ms) pour éviter les captures intermédiaires, et respectant un temps de cooldown.

Règles de déduplication et signature :

- Hash spatial : Le contenu textuel ou sensible est ignoré pour produire la signature ; seuls la hiérarchie et les attributs géométriques (tailles, positions) sont hashes.
- Mise en cache : Si la signature générée correspond au dernier LOM capturé (`_lastSignature`), la capture est avortée (aucun changement structurel).
- LomRef : Si la signature existe déjà dans le cache de la session courante (l'utilisateur revient sur un état précédent), la librairie génère un `LomRef` léger (uniquement l'ID et le timestamp) au lieu de renvoyer l'arbre complet.

## Relations métier

- Un `Chunk` contient `1..n` records ;
- Un `Record` appartient à `1` seul chunk ;
- Un `Record` d'événement référence toujours le contexte visuel via le `lom_ref` du LOM actif au moment de l'interaction ;
- Les événements et LOMs sont horodatés indépendamment avec des timestamps absolus ;
- Le LOM complet n'est envoyé qu'une seule fois par session pour une signature spatiale donnée.

## Représentation Cible Minimale

Ces structures servent de contrat d'implémentation pour les SDKs (Dart/Flutter, TypeScript/React Native).

### Structures LOM 

```dart
@immutable
abstract class LomAbstract {
  final String id;
  final int timestamp;
  final Root? root;

  const LomAbstract({required this.id, required this.timestamp, this.root});
  Map<String, dynamic> toMap();
}

class Lom extends LomAbstract {
  final int width;
  final int height;

  const Lom({
    required super.id,
    required super.timestamp,
    required this.width,
    required this.height,
    super.root,
  });

  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'ts': timestamp,
    'w': width,
    'h': height,
    'r': root?.toMap() ?? "",
  };
}

class LomRef extends LomAbstract {
  const LomRef({required super.id, required super.timestamp});

  @override
  Map<String, dynamic> toMap() => {'ref': id, 'ts': timestamp};
}

class Root {
  final int id;
  final String objectId;
  final String widgetType;
  final String renderType;
  final Rect box;
  final List<Root> children;
  
  // Constructeur et toMap()...
}
```

### Structure Chunk

```dart
class Chunk {
  final String sId; // Session ID
  final int timestamp;
  
  final List<LomAbstract> loms;
  final List<ExplorationEvent> explorationEvents;
  final List<ActionEvent> actionsEvents;

  Chunk(this.sId)
    : timestamp = DateTime.now().millisecondsSinceEpoch,
      actionsEvents = [],
      explorationEvents = [],
      loms = [];

  Map<String, dynamic> toMap() => {
    'lib_v': "2.0.0",
    'ts': timestamp,
    'sid': sId,
    'loms': loms.map((x) => x.toMap()).toList(),
    'pnt': [], // Performance Metrics
    'ee': explorationEvents.map((x) => x.concatenateString()).toList(),
    'ae': actionsEvents.map((x) => x.concatenateString()).toList(),
  };
}
```

### Règles de frontière réseau (Network Boundary)

- Le backend reçoit exclusivement des `Chunks`, jamais de flux d'événements unitaires en temps réel.
- Le cycle de `flush` (ex: 10s) vérifie s'il existe des records en mémoire ; si oui, il ferme le `Chunk` courant, l'envoie, et en initialise un nouveau.
- Un `flush` prioritaire (urgent) est déclenché par le `Controller` lorsque l'application passe en arrière-plan (Lifecycle `paused` / `inactive`) pour éviter la perte de données si l'OS tue le processus.

