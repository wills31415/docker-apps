#!/usr/bin/env bash
# =============================================================================
# fix-steamdeck-profiles.sh — Utilitaire one-shot pour le SteamDeck (ModrinthApp).
#
# Résout deux soucis :
#   1. Le profil prod (affiché "CoupaingCraft" dans la GUI) pointe vers le
#      dossier disque "pack" — héritage d'un ancien import. On renomme le
#      dossier physique en "CoupaingCraft" et on met à jour la DB ModrinthApp.
#   2. Le nouveau profil test est vide de configs perso (Sodium, options,
#      JourneyMap data, etc.). On clone les configs du profil prod vers test.
#
# IMPORTANT : ferme ModrinthApp AVANT de lancer le script (sinon DB lockée).
#
# Usage :
#   curl -fsSL http://90.79.99.178:25566/fix-steamdeck-profiles.sh -o ~/fix.sh
#   chmod +x ~/fix.sh
#   ~/fix.sh                                   # avec defaults (Flatpak SteamDeck)
#   ~/fix.sh --dry-run                         # affiche ce qui serait fait
#   PROD_OLD_NAME=pack PROD_NEW_NAME=CoupaingCraft TEST_NAME=coupaing-craft-test ~/fix.sh
#
# Override possible :
#   ROOT            chemin racine ModrinthApp
#                   (default: ~/.var/app/com.modrinth.theseus/data/ModrinthApp)
#   PROD_OLD_NAME   nom actuel du dossier prod (default: pack)
#   PROD_NEW_NAME   nom cible (default: CoupaingCraft)
#   TEST_NAME       nom du dossier du profil test à hydrater
#                   (default: auto-détection parmi coupaing-craft-test,
#                   CoupaingCraft-Test, pack-test, test)
# =============================================================================
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

ROOT="${ROOT:-$HOME/.var/app/com.modrinth.theseus/data/ModrinthApp}"
PROFILES="$ROOT/profiles"
DB="$ROOT/app.db"

PROD_OLD_NAME="${PROD_OLD_NAME:-pack}"
PROD_NEW_NAME="${PROD_NEW_NAME:-coupaing-craft}"

# Items à cloner du profil prod vers le profil test.
# On NE copie PAS : mods/, resourcepacks/, shaderpacks/, datapacks/ (gérés par
# update-client-test.sh) ; logs/, crash-reports/ (specifiques à chaque session) ;
# saves/ (server-side, inutile en multi).
CLONE_ITEMS=(
  "config"
  "options.txt"
  "servers.dat"
  "journeymap"
  "yosbr"
  "schematics"
  "screenshots"
)

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

# ─── Sanity checks ───────────────────────────────────────────────────────────
[[ -d "$PROFILES" ]] || { echo "❌ Dossier profils introuvable : $PROFILES" >&2; exit 1; }
[[ -f "$DB" ]] || { echo "❌ DB ModrinthApp introuvable : $DB" >&2; exit 1; }

# Test du verrou DB (si ModrinthApp tourne, le BEGIN IMMEDIATE échoue avec "locked")
if sqlite3 -cmd ".timeout 200" "$DB" "BEGIN IMMEDIATE; ROLLBACK;" 2>&1 | grep -qiE "locked|busy"; then
  echo "❌ DB lockée — ferme ModrinthApp et relance le script." >&2
  exit 1
fi

echo "📁 ModrinthApp root : $ROOT"
echo "📂 Profils existants :"
for d in "$PROFILES"/*/; do
  [[ -d "$d" ]] && echo "    - $(basename "$d")"
done
echo ""

# ─── Auto-détection du profil test si TEST_NAME pas fourni ───────────────────
if [[ -z "${TEST_NAME:-}" ]]; then
  for candidate in coupaing-craft-test CoupaingCraft-Test pack-test test "coupaing-craft (test)"; do
    if [[ -d "$PROFILES/$candidate" ]]; then
      TEST_NAME="$candidate"
      break
    fi
  done
fi

# ─── Partie 1 : Rename prod ──────────────────────────────────────────────────
echo "━━━ Partie 1 : Renommage profil prod ━━━"

if [[ ! -d "$PROFILES/$PROD_OLD_NAME" ]]; then
  echo "ℹ️  Profil source '$PROD_OLD_NAME' introuvable — skip rename."
elif [[ -d "$PROFILES/$PROD_NEW_NAME" ]]; then
  echo "⚠️  Cible '$PROD_NEW_NAME' existe déjà — skip rename (possible déjà fait ou conflit)."
else
  echo "  Backup DB : $DB.bak.$(date +%Y%m%d-%H%M%S)"
  run cp "$DB" "$DB.bak.$(date +%Y%m%d-%H%M%S)"
  echo "  mv $PROFILES/$PROD_OLD_NAME → $PROFILES/$PROD_NEW_NAME"
  run mv "$PROFILES/$PROD_OLD_NAME" "$PROFILES/$PROD_NEW_NAME"
  echo "  UPDATE profiles SET path='$PROD_NEW_NAME', name='$PROD_NEW_NAME' WHERE path='$PROD_OLD_NAME'"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    sqlite3 "$DB" "UPDATE profiles SET path='$PROD_NEW_NAME', name='$PROD_NEW_NAME' WHERE path='$PROD_OLD_NAME';"
  fi
  echo "✅ Profil prod : '$PROD_OLD_NAME' → '$PROD_NEW_NAME'"
fi
echo ""

# ─── Partie 2 : Clone configs prod → test ────────────────────────────────────
echo "━━━ Partie 2 : Clone configs prod → test ━━━"

# En dry-run, le mv de la partie 1 n'a pas eu lieu — on lit donc depuis OLD.
# En mode réel, le rename est fait, on lit depuis NEW.
if [[ -d "$PROFILES/$PROD_NEW_NAME" ]]; then
  SRC="$PROFILES/$PROD_NEW_NAME"
elif [[ -d "$PROFILES/$PROD_OLD_NAME" ]]; then
  SRC="$PROFILES/$PROD_OLD_NAME"
  echo "ℹ️  (dry-run ou rename skipé) lecture depuis '$PROD_OLD_NAME'"
else
  echo "❌ Aucun profil prod trouvé (ni '$PROD_NEW_NAME' ni '$PROD_OLD_NAME')" >&2
  exit 1
fi
DST="$PROFILES/${TEST_NAME:-}"

if [[ -z "${TEST_NAME:-}" ]]; then
  echo "❌ Aucun profil test détecté."
  echo "   Crée un profil test dans ModrinthApp (ex: nom 'coupaing-craft-test')"
  echo "   puis relance avec : TEST_NAME=NomDuProfil $0"
  exit 1
fi
[[ -d "$DST" ]] || { echo "❌ Profil test $DST introuvable" >&2; exit 1; }

echo "  Source     : $SRC"
echo "  Destination: $DST"
echo "  Items      : ${CLONE_ITEMS[*]}"
echo ""

for item in "${CLONE_ITEMS[@]}"; do
  if [[ -e "$SRC/$item" ]]; then
    if [[ -e "$DST/$item" ]]; then
      backup="$DST/${item}.bak.$(date +%Y%m%d-%H%M%S)"
      echo "  📋 $item (existe — backup → $(basename "$backup"))"
      run mv "$DST/$item" "$backup"
    else
      echo "  📋 $item"
    fi
    run cp -r "$SRC/$item" "$DST/"
  else
    echo "  ⏭️  $item (absent côté prod, skip)"
  fi
done

echo ""
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "🛑 dry-run : aucune modification appliquée. Relance sans --dry-run."
else
  echo "✅ Terminé. Relance ModrinthApp."
  echo ""
  echo "Si le profil prod ne s'affiche plus correctement après ouverture :"
  echo "  - Restaurer : cp $DB.bak.<timestamp> $DB"
  echo "  - Et : mv $PROFILES/$PROD_NEW_NAME $PROFILES/$PROD_OLD_NAME"
fi
