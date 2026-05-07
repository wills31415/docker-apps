# Datapacks maison

Sources versionnées des datapacks que `pre-up.sh` zip + déploie automatiquement
dans `shared/data/world/datapacks/` à chaque `da up`. Survivent aux wipes du
monde.

## Structure attendue

```
config/datapacks/
├── README.md                  ← ce fichier
└── <nom-datapack>/
    ├── pack.mcmeta
    └── data/<namespace>/...
```

À chaque `da up` :
1. `pre-up.sh` itère sur les sous-dossiers
2. Chaque sous-dossier `<nom>/` est zippé en `<nom>.zip`
3. Le zip est posé dans `shared/data/world/datapacks/`
4. Le datapack est auto-détecté par MC au boot du monde (vanilla scan)

Pour activer un datapack existant en jeu : `/datapack enable "file/<nom>.zip"`.

## Datapacks actifs

| Nom | But |
|---|---|
| `coupaing-craft-fixes` | Fixes de recettes manquantes — actuellement : tin_block ↔ tin_ingot et raw_tin_block ↔ raw_tin (oubliés par create_dd 0.1d). |
