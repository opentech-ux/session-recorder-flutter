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

Démarrage :

- Si `endpoint` est vide, le reporter ne démarre pas.
- Si le timer est déjà actif, `start()` ne fait rien.
- Sinon, un `Timer.periodic` déclenche `_flush()` toutes les 10 secondes.

Arrêt :

- `stop()` annule le timer et remet sa référence à `null`.

## Flush périodique

Flux actuel :

```text
Timer tick
  -> _flush()
    -> context.extractChunk()
      -> null si chunk vide
      -> chunk fermé si non vide
    -> return si shouldSend == false
    -> _send(chunk)
```

Point important :

- En debug, si `debugSendSession` vaut `false`, `shouldSend` vaut `false`.
- Dans ce cas, `_flush()` extrait quand même le chunk puis le jette sans envoyer.
- Ce comportement évite les envois de test involontaires, mais signifie que les données debug ne sont pas conservées.

## Envoi réseau

`_send(chunk)` :

- sérialise le chunk avec `chunk.toJson()`;
- parse `config.endpoint` en `Uri`;
- exécute un `POST`;
- ajoute le header `Content-Type: application/json; charset=UTF-8`;
- considère les status hors `2xx` comme erreurs HTTP.

Erreurs interceptées :

- `SocketException`
- `TimeoutException`
- `FormatException`
- `HttpException`
- toute autre exception

Comportement actuel :

- Les erreurs sont loggées via `SessionLogger.error`.
- Il n'existe pas de retry.
- Il n'existe pas de queue persistante.
- En debug, les certificats invalides sont acceptés par `badCertificateCallback`.

## Endpoint et validation

`SessionRecorderConfig.validate()` définit une forme d'endpoint attendue :

```text
https://[subdomain].ux-key.com/endpoint
```

État actuel :

- La méthode existe.
- L'appel est commenté dans `SessionRecorder.init`.
- Si l'endpoint est vide, le reporter ne démarre pas.
- Si l'endpoint est invalide mais non vide, l'erreur peut arriver au moment de l'envoi.

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
- `error` est toujours délégué.
- Le logger par défaut ne logge pas en release.
