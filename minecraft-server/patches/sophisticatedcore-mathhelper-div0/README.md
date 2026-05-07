# Patch : SophisticatedCore — guard div/0 dans `intMaxCappedMultiply`

## Symptôme

Crash client `java.lang.ArithmeticException: / by zero` au rendering d'un
écran Sophisticated (sac à dos, coffre, baril) :

```
at sophisticatedcore.util.MathHelper.intMaxCappedMultiply(MathHelper.java:13)
at sophisticatedcore.inventory.InventoryHandler.getBaseStackLimit(InventoryHandler.java:187)
at sophisticatedcore.client.gui.StorageScreenBase.method_25394(...)
```

## Cause

Bytecode upstream non protégé contre `a == 0` :

```
0: ldc  2147483647
2: iload_0          ← a
3: idiv             ← MAX / a → DIV/0 si a == 0
```

Présent dans **toutes les versions** : Forge, NeoForge, port Fabric, jusqu'à
la 1.21.11-1.4.36 (décembre 2025). Bug upstream non fixé.

Sur Forge/NeoForge un autre appel intermédiaire empêche normalement `a == 0`
d'arriver, mais le port Fabric n'a pas cette protection → crash en ouvrant
un Sophisticated containing certain items (polymer-rendered, modded items
avec `maxStackSize=0`) ou parfois même des conteneurs vides.

## Fix

Ajouter un guard en début de méthode :

```java
public static int intMaxCappedMultiply(int a, int b) {
    if (a == 0 || b == 0) return 0;  // ← ajouté
    return Integer.MAX_VALUE / a < b ? Integer.MAX_VALUE : a * b;
}
```

## Application

```bash
./apply.sh ~/.local/share/ModrinthApp/profiles/<profil>/mods/sophisticatedcore-X.Y.Z.jar
```

Idempotent : ré-exécutable sans risque, détecte si déjà patché.

À ré-appliquer après chaque update upstream du mod tant que le bug n'est pas
fixé en amont.

Le jar patché part automatiquement dans `overrides/` du `.mrpack` (son SHA-1
ne matche plus Modrinth) → préservé à chaque `sync-pack.sh`.
