#!/usr/bin/env bash
# =============================================================================
# Patch idempotent : SophisticatedCore — guard div/0 dans intMaxCappedMultiply
#
# Usage :
#   ./apply.sh <chemin/vers/sophisticatedcore-X.Y.Z.jar>
#
# Effet :
#   Compile MathHelper.java (Java 17, target 17), injecte le .class dans le jar
#   in-place. Idempotent — relancer sur un jar déjà patché ne casse rien.
#
# Pourquoi :
#   La méthode publique `intMaxCappedMultiply(int a, int b)` du mod fait
#   `Integer.MAX_VALUE / a` sans guard. Si a=0 (item dont getMaxStackSize()==0,
#   ou baseSlotLimit=0), ArithmeticException : / by zero.
#
#   Reproduit dans toutes les versions Forge / NeoForge / Fabric port,
#   y compris la dernière 1.21.11-1.4.36 (décembre 2025). Bug upstream non fixé.
#
#   Sur Forge un autre appel intermédiaire empêche normalement a=0 d'arriver,
#   mais le port Fabric n'a pas cette protection → crash en ouvrant un sac à
#   dos ou un coffre Sophisticated avec certains items "exotiques" (polymer,
#   modded items à maxStackSize=0) ou même des coffres vides selon l'état NBT.
# =============================================================================
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage : $0 <sophisticatedcore-X.Y.Z.jar>" >&2
    exit 1
fi

JAR="$1"
if [[ ! -f "$JAR" ]]; then
    echo "❌ Fichier introuvable : $JAR" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/MathHelper.java"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Compile
mkdir -p "$WORK/net/p3pp3rf1y/sophisticatedcore/util"
cp "$SRC" "$WORK/net/p3pp3rf1y/sophisticatedcore/util/MathHelper.java"
( cd "$WORK" && javac --release 17 net/p3pp3rf1y/sophisticatedcore/util/MathHelper.java )

# Vérif idempotence : compare le bytecode de intMaxCappedMultiply.
# Le bytecode patché commence par "iload_0; ifeq" ; le bytecode original par "ldc".
unzip -p "$JAR" net/p3pp3rf1y/sophisticatedcore/util/MathHelper.class > "$WORK/current.class"
CURRENT_OPCODES="$(javap -p -c "$WORK/current.class" 2>/dev/null \
    | awk '/intMaxCappedMultiply/{found=1; next} found && /Code:/{p=1; next} p && /^  [a-z]/{exit} p' \
    | head -3 | tr -d ' \n')"

if [[ "$CURRENT_OPCODES" == *"iload_0"*"ifeq"* ]]; then
    echo "✅ Jar déjà patché : $JAR"
    echo "   SHA-1 : $(sha1sum "$JAR" | cut -d' ' -f1)"
    exit 0
fi

# Injection
( cd "$WORK" && jar uf "$JAR" net/p3pp3rf1y/sophisticatedcore/util/MathHelper.class )
echo "✅ Patché : $JAR"
echo "   SHA-1 : $(sha1sum "$JAR" | cut -d' ' -f1)"
