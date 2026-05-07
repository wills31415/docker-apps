# Resource packs maison

Sources versionnées des resource packs distribués via le `.mrpack` aux clients.
Au prochain `sync-pack.sh`, chaque sous-dossier ici est zippé dans
`<master>/resourcepacks/<nom>.zip` (si plus récent que le zip existant) puis
inclus dans le manifest comme un asset `resourcepacks/`.

## Structure

```
resourcepacks/
├── README.md
└── <nom-pack>/
    ├── pack.mcmeta
    └── assets/<namespace>/lang/...   ← ou textures/, models/, etc.
```

## Resource packs actifs

| Nom | But |
|---|---|
| `coupaing-craft-fixes-rp` | Descriptions d'enchantements manquantes — actuellement : `harvest-enchantment.harvesting.desc` (en/fr). |
