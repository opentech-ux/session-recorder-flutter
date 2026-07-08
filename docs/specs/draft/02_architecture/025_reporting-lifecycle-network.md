# 025 - Reporting, lifecycle et réseau

## Statut

Draft

## But

Ce document décrit comment les données accumulées sont transformées en chunks, quand elles sont envoyées et comment le SDK réagit au lifecycle applicatif.

## Chunks

Le `ContextImpl` maintient un chunk courant.

Le chunk contient :

- `sid`
- `ts`
- `lib_v`
- `type`
- `loms`
- `pnt`
- `ee`
- `ae`

Règles :

- Un chunk vide n'est jamais retourné par `extractChunk`.
- Quand un chunk non vide est extrait, le contexte crée immédiatement un nouveau chunk avec le même `sid`.
- `pnt` est présent dans le payload mais reste vide à ce stade.

## SessionRecorderReporter

`SessionRecorderReporter` est responsable du timer et de l'envoi HTTP.

État :

- `_timer` : timer périodique actif ou `null`.
- `_interval` : 10 secondes.
- `_httpClient` : `IOClient` basé sur `HttpClient`.
- une file mémoire courte de chunks en attente.
- un garde de flush empêchant les envois concurrents.

Démarrage :

- Si `endpoint` est vide, le reporter ne démarre pas.
- Si le timer est déjà actif, `start()` ne fait rien.
- Sinon, un `Timer.periodic` déclenche `_flush()` toutes les 10 secondes.

Arrêt :

- `stop()` annule le timer et remet sa référence à `null`.
- `close()` annule le timer, vide la file mémoire courte et ferme le client HTTP.

## Flush périodique

Flux actuel :

```text
Timer tick
  -> _flush()
    -> context.extractChunk()
      -> null si chunk vide
      -> chunk fermé si non vide
    -> return si shouldSend == false
    -> enqueue chunk si non nul
    -> drain de la file mémoire
```

Point important :

- En debug, si `debugSendSession` vaut `false`, `shouldSend` vaut `false`.
- Dans ce cas, `_flush()` extrait quand même le chunk puis le jette sans envoyer.
- Ce comportement évite les envois de test involontaires, mais signifie que les données debug ne sont pas conservées.
- Si un envoi est déjà en cours, un nouveau tick de flush est ignoré.
- Les chunks échoués peuvent être conservés en mémoire courte pour un seul retry.

## Envoi réseau

`_send(chunk)` :

- sérialise le chunk avec `chunk.toJson()`;
- parse `config.endpoint` en `Uri`;
- exécute un `POST`;
- ajoute le header `Content-Type: application/json; charset=UTF-8`;
- considère les status hors `2xx` comme erreurs HTTP.
- applique un timeout HTTP de 5 secondes.

Retry :

- la file mémoire conserve au maximum 3 chunks ;
- chaque chunk échoué a droit à 1 retry ;
- si la file est pleine, le chunk le plus ancien est abandonné ;
- les LOM complets abandonnés sont gardés dans une cache mémoire bornée, séparée du cache de déduplication, afin de remplacer un futur `LomRef` si le serveur ne connaît pas encore ce ref ;
- aucune persistance disque n'est utilisée.

Erreurs interceptées :

- `SocketException`
- `TimeoutException`
- `FormatException`
- `HttpException`
- toute autre exception

Comportement actuel :

- Les erreurs sont loggées via `SessionLogger.error`.
- Il existe une seule tentative de retry en mémoire par chunk.
- Il n'existe pas de queue persistante sur disque.
- En debug, les certificats invalides sont acceptés par `badCertificateCallback`.

## Endpoint et validation

`SessionRecorderConfig.validate()` définit une forme d'endpoint attendue :

```text
https://[subdomain].ux-key.com/endpoint
```

État actuel :

- La méthode existe.
- L'appel est temporairement commenté dans `SessionRecorder.init` pour permettre les tests sur endpoint local.
- Si l'endpoint est vide, le reporter ne démarre pas.
- Tant que `validate()` est commenté, un endpoint invalide est traité par le reporter et échoue sans bloquer l'application.

Règle :

- avant publication, le format accepté doit redevenir strictement `https://[subdomain].ux-key.com/endpoint`.

## Lifecycle applicatif

`SessionLifecycleObserver` est un mixin utilisé par `SessionRecorderWidget`.

Transitions actuelles :

- `resumed` : relance le reporting.
- `paused`, `inactive`, `hidden`, `detached` : appelle `onSessionSuspended()` puis stoppe le reporting.

Dans `SessionRecorderWidget`, `onSessionSuspended()` appelle `_dispatchPendingEvents()`.

Effet :

- `GestureCollector.forceRecordCollector()` est appelé.
- `ScrollCollector.forceRecordCollector()` est appelé.
- Les gestes et scrolls en cours sont drainés dans le chunk courant.

Dispose interne :

- `SessionRecorderWidget.dispose` draine les collectors ;
- la callback d'interruption du controller est nettoyée avec `onInterrupt(null)` ;
- le reporting est arrêté et le reporter interne est fermé ;
- le detector LOM restaure son hook `onBuildScheduled` si possible ;
- le contexte nettoie les références locales au LOM courant, aux roots connus, à la route courante et au chunk en mémoire.

Limite actuelle :

- Aucun flush réseau urgent n'est déclenché par le lifecycle.
- Si le timer est arrêté avant le prochain tick, les données restent dans le chunk courant tant que le processus survit.

## Inactivité

`InactivityDetector` arrête le reporting après 30 secondes sans action ou exploration.

Flux :

```text
recordAction / recordExploration
  -> controller.pingInactivity()
    -> reset timer 30s

timer expire
  -> onInactive
  -> controller.stopReporting()

prochaine interaction
  -> onActive
  -> controller.startReporting()
```

Note :

- `recordLom` ne ping pas l'inactivité.
- Une navigation qui capture seulement un LOM ne suffit pas à maintenir le reporter actif, sauf si elle a aussi drainé un événement utilisateur.

## Logs

`SessionLogger` délègue les logs à une callback fournie par la configuration.

Règles :

- `info`, `verbose` et `warning` respectent `debugLog`.
- `error` est délégué en debug/profil ; en release, il respecte `debugLog`.
- Le logger par défaut ne logge pas en release.
