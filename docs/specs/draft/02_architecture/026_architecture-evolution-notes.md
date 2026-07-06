# 026 - Notes d'évolution de l'architecture

## Statut

Draft

## But

Ce document liste les points d'évolution connus de l'architecture actuelle.
Il ne remplace pas les specs fonctionnelles ; il sert de pense-bête technique avant modification du code.

## Évolutions déjà identifiées

### Ajouter `lom_ref` aux événements

État actuel :

- Les `ActionEvent` référencent le contexte spatial via `zone`.
- Les `ExplorationEvent` ne portent pas de `zone`.
- Aucun événement ne sérialise encore `lom_ref`.

Cible :

- Ajouter `:lom_ref` à la fin de chaque chaîne `ae` et `ee`.
- Le `lom_ref` doit correspondre au LOM actif au moment de l'interaction.

Question d'architecture :

- Faut-il stocker le `lom_ref` dans chaque modèle d'événement au moment de la capture, ou l'ajouter lors de la sérialisation du chunk ?

Préférence probable :

- Le stocker au moment de la capture pour conserver le contexte exact de l'interaction, même si le LOM courant change avant le prochain flush.

### Implémenter `pnt`

État actuel :

- `pnt` est toujours une liste vide.

Cible :

- Ajouter un collector de métriques de performance.
- Garder ce collector optionnel ou peu coûteux.
- Éviter toute mesure fréquente qui pourrait impacter le thread UI.

Questions ouvertes :

- Quelles métriques sont autorisées ?
- À quelle fréquence les capturer ?
- Faut-il les envoyer comme records périodiques ou comme résumé par chunk ?

### Clarifier le comportement de `LomRef` et des zones

État actuel :

- Un `LomRef` peut devenir le LOM courant.
- Si ce `LomRef` ne contient pas de `root`, la résolution de zone retourne `null`, puis les actions utilisent `z0`.

Risque :

- Sur un écran déjà vu et dédupliqué, les actions peuvent perdre leur zone précise.

Options possibles :

- Conserver en mémoire le dernier arbre complet par signature pour la résolution locale.
- Garder `LomRef` léger dans le payload, mais associer localement son `id` à un `Root`.
- Ne pas remplacer `_currentLom` par un `LomRef` sans `root` pour la résolution des zones.

### Flush urgent lifecycle

État actuel :

- Le lifecycle suspendu draine les collectors.
- Il ne force pas d'envoi réseau immédiat.

Cible possible :

- Ajouter une API interne `flushNow()` au reporter ou au controller.
- L'appeler après le drain lifecycle.
- Encadrer cette API pour éviter les appels concurrents avec le timer périodique.

Contraintes :

- Ne pas bloquer le thread UI.
- Ne pas provoquer de crash si l'OS suspend rapidement l'application.
- Accepter que l'envoi puisse échouer silencieusement.

### Réactiver la validation d'endpoint

État actuel :

- `SessionRecorderConfig.validate()` existe.
- L'appel est commenté dans `SessionRecorder.init`.

Cible possible :

- Réactiver la validation.
- Décider si une configuration invalide doit throw, logger puis passer en no-op, ou uniquement désactiver le reporting.

### Adapter la déduplication LOM

État actuel :

- Le cache de signature est consulté avant `_lastSignature`.
- Toute signature connue retourne un `LomRef`.

Question :

- Le dernier LOM identique doit-il produire un `LomRef`, ou ne rien enregistrer ?

Impact :

- `LomRef` permet de dater un retour vers un état visuel connu.
- Ne rien enregistrer réduit encore le payload mais peut masquer certains changements de contexte.

### Tests manquants

Zones à couvrir en priorité :

- sérialisation `Chunk`, `ActionEvent`, `ExplorationEvent`, `Lom`, `LomRef`, `Root` ;
- déduplication LOM et génération `LomRef` ;
- résolution de `zone` via `TapTreeFinder` ;
- sampling drag/pinch ;
- scroll start/end et drain forcé ;
- lifecycle suspendu sans flush urgent ;
- comportement `shouldSend == false`.

## Règles pour les futures modifications

- Préserver la surface publique minimale.
- Garder les collectors sans dépendance réseau directe.
- Garder `ContextImpl` comme propriétaire unique du chunk courant.
- Ne pas introduire de capture de texte ou de valeur utilisateur.
- Mesurer l'impact UI avant toute capture plus fréquente.
- Documenter tout changement de payload dans `01_context` et `02_architecture`.
