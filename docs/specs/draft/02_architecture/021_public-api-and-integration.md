# 021 - API publique et intégration

## Statut

Draft

## But

Ce document décrit la surface publique actuelle du SDK et le rôle des composants que l'application cliente doit intégrer.

## Surface publique exposée

Le fichier `lib/session_recorder.dart` expose uniquement :

- `SessionRecorder`
- `SessionRecorderConfig`
- `SessionRecorderWidget`
- `SessionNavigatorObserver`

Tout le reste du package vit dans `lib/src/` et doit être traité comme interne.

## Séquence d'intégration

L'intégration standard repose sur trois étapes :

1. Initialiser le SDK avec `SessionRecorder.init(config)`.
2. Envelopper l'application avec `SessionRecorderWidget`.
3. Attacher un `SessionNavigatorObserver` au routeur Flutter.

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SessionRecorder.init(
    SessionRecorderConfig(endpoint: 'https://example.ux-key.com/endpoint'),
  );

  runApp(
    SessionRecorderWidget(
      child: MaterialApp(
        navigatorObservers: [SessionNavigatorObserver()],
        home: const HomeScreen(),
      ),
    ),
  );
}
```

## SessionRecorder

`SessionRecorder` est la façade statique du SDK.

Responsabilités :

- conserver l'instance interne de `SessionRecorderEngineInternal` ;
- exposer `init(config)` comme point d'entrée public ;
- empêcher une double initialisation ;
- configurer le logger interne ;
- démarrer le moteur ;
- repasser en `NoOpSessionRecorderEngine` si l'initialisation échoue.

Règles :

- `init` doit être appelé une seule fois au démarrage de l'application.
- `SessionRecorder.engine` est marqué `@internal` et ne doit pas être utilisé par le client.
- Avant initialisation, ou après une erreur d'initialisation, le SDK fonctionne en mode no-op.

Note actuelle :

- `SessionRecorderConfig.validate()` existe, mais son appel est actuellement commenté dans `SessionRecorder.init`.

## SessionRecorderConfig

`SessionRecorderConfig` décrit les paramètres globaux du SDK.

Champs actuels :

- `endpoint` : URL de réception des chunks.
- `debugLog` : active les logs internes.
- `debugShowTree` : affiche l'overlay debug du LOM.
- `debugSendSession` : autorise l'envoi réseau en debug.
- `shouldSend` : dérive de `kReleaseMode || debugSendSession`.
- `logger` : callback de logs délégué à l'application cliente.

Règles actuelles :

- En debug, les données ne sont pas envoyées par défaut.
- En release, `shouldSend` vaut toujours `true`.
- Si `endpoint` est vide, le reporter ne démarre pas son timer.

## SessionRecorderWidget

`SessionRecorderWidget` est le wrapper racine qui active la capture comportementale.

Responsabilités :

- installer un `Listener` global pour les événements pointeur ;
- installer un `NotificationListener<ScrollNotification>` pour les scrolls ;
- créer un `GestureCollector` et un `ScrollCollector` ;
- enregistrer une callback d'interruption dans le controller ;
- drainer les collectors lors du dispose ou du lifecycle suspendu ;
- vérifier après la première frame qu'un `SessionNavigatorObserver` est attaché ;
- afficher `LomTreeOverlay` si `debugShowTree` est actif.

Règle importante :

- Le widget doit être installé une seule fois dans l'application pour éviter les captures dupliquées.

## Factory SessionRecorderWidget.observer

`SessionRecorderWidget.observer` crée un `SessionNavigatorObserver` puis le passe au builder.
Cette API facilite le cas `MaterialApp.navigatorObservers`.

```dart
SessionRecorderWidget.observer(
  builder: (observer) => MaterialApp(
    navigatorObservers: [observer],
    home: const HomeScreen(),
  ),
);
```

## SessionNavigatorObserver

`SessionNavigatorObserver` est un `NavigatorObserver` Flutter.

Responsabilités :

- s'enregistrer dans le `ControllerImpl` à sa construction ;
- détecter `didPush`, `didPop` et `didReplace` ;
- attendre la stabilisation de l'animation de route ;
- transmettre le `subtreeContext` de la route au context runtime ;
- demander une capture LOM après navigation ;
- interrompre les collectors pour enregistrer les gestes/scrolls en cours avant changement d'écran.

Il peut être installé plusieurs fois, notamment dans des configurations `GoRouter` avec plusieurs navigators.
