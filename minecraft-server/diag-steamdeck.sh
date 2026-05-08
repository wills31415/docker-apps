#!/usr/bin/env bash
# =============================================================================
# diag-steamdeck.sh — Diagnostic ModrinthApp côté SteamDeck.
# Affiche les profils + indique si a-few-more-enchantments est chargé.
# =============================================================================
set -euo pipefail

ROOT="${ROOT:-/home/deck/.var/app/com.modrinth.ModrinthApp/data/ModrinthApp}"
DB="$ROOT/app.db"
PROFILES="$ROOT/profiles"

[[ -d "$PROFILES" ]] || { echo "❌ Profils introuvables : $PROFILES"; exit 1; }

echo "=== Profils ModrinthApp ==="
if [[ -f "$DB" ]]; then
  sqlite3 -header -column "$DB" "SELECT path AS dir, name, game_version AS mc FROM profiles;" 2>/dev/null \
    || echo "(impossible de lire la DB — peut-être lockée si ModrinthApp est ouvert)"
else
  ls -d "$PROFILES"/*/
fi

echo ""
echo "=== Mods test (FallingTree, VeinMining, Soulbound, RightClickHarvest, Grind, JamLib) par profil ==="
for p in "$PROFILES"/*/; do
  name=$(basename "$p")
  echo "── $name ──"
  for keyword in falling veinmining soulbound rightclick grind jamlib treeharv collective; do
    match=$(ls "$p/mods/" 2>/dev/null | grep -iE "$keyword" || true)
    [[ -n "$match" ]] && echo "    ✅ $match"
  done
done

echo ""
echo "=== Dernière session de chaque profil (qu'as-tu lancé en dernier ?) ==="
for p in "$PROFILES"/*/; do
  name=$(basename "$p")
  log="$p/logs/latest.log"
  if [[ -f "$log" ]]; then
    mtime=$(stat -c '%y' "$log" 2>/dev/null | cut -d. -f1)
    line=$(grep -E "Loading [0-9]+ mods" "$log" 2>/dev/null | head -1)
    afme=$(grep -ciE "few_more|a-few-more-enchant" "$log" 2>/dev/null || true)
    echo "  $name  (latest.log: $mtime)"
    [[ -n "$line" ]] && echo "       $line"
    [[ "$afme" -gt 0 ]] && echo "       ✅ a-few-more-enchantments mentionné $afme× dans le log" \
                       || echo "       ❌ a-few-more-enchantments JAMAIS mentionné dans le log"
  else
    echo "  $name  (jamais lancé — pas de latest.log)"
  fi
done

echo ""
echo "=== Conclusion ==="
echo "Le profil avec le timestamp le plus récent = celui que tu viens de lancer."
echo "Si c'est 'coupaing-craft' (prod) → ferme MC, sélectionne coupaing-craft-test"
echo "                                   dans ModrinthApp et relance."
echo "Si c'est 'coupaing-craft-test' avec ❌ → le mod n'a pas été chargé."
echo "                                          On creusera avec le crash log."
