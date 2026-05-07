#!/usr/bin/env bash
# =============================================================================
# update-client.sh — Met à jour le profil ModrinthApp d'un client (SteamDeck)
# vers la dernière version du pack, SANS toucher aux configs ni aux data.
#
# Usage :
#   ./update-client.sh                # Auto-détecte le profil par défaut.
#   ./update-client.sh /chemin/profil # Override explicite.
#
# Variables d'env :
#   PACK_URL   URL du .mrpack (default: http://90.79.99.178:25566/coupaing-craft.mrpack)
#   PACK_NAME  Nom du dossier de profil ModrinthApp (default: CoupaingCraft)
#
# Effet :
#   1. Télécharge le dernier .mrpack depuis Dynmap HTTP.
#   2. Calcule le diff entre le manifeste et le profil local.
#   3. mods/ + resourcepacks/ + shaderpacks/ : ajoute / supprime / met à jour
#      les fichiers selon le manifeste. Les fichiers obsolètes sont DÉPLACÉS
#      dans .update-backup/<timestamp>/ (jamais supprimés).
#   4. NE TOUCHE PAS : config/, options.txt, journeymap/, screenshots/, saves/,
#      logs/, crash-reports/, jei/, sodium/, et tout le reste.
#
# Conçu pour SteamDeck Flatpak (~/.var/app/com.modrinth.theseus/...). Auto-fallback
# pour les installs Linux native et Windows.
# =============================================================================
set -euo pipefail

PACK_URL="${PACK_URL:-http://90.79.99.178:25566/coupaing-craft.mrpack}"
# PACK_NAME peut être explicitement passé (ex : PACK_NAME=AutreProfil ./update-client.sh).
# Sinon, on teste plusieurs noms de profil courants — l'historique des imports
# successifs a laissé des profils nommés différemment (manifest.name, filename
# du .mrpack au moment de l'import, etc.).
PACK_NAMES_DEFAULT=("CoupaingCraft" "coupaing-craft" "pack")
if [[ -n "${PACK_NAME:-}" ]]; then
  PACK_NAMES=("$PACK_NAME")
else
  PACK_NAMES=("${PACK_NAMES_DEFAULT[@]}")
fi

# Racines ModrinthApp possibles (Flatpak SteamDeck, Linux natif, Windows).
PROFILES_ROOTS=(
  "$HOME/.var/app/com.modrinth.theseus/data/ModrinthApp/profiles"  # Flatpak (SteamDeck/Linux)
  "$HOME/.local/share/ModrinthApp/profiles"                          # Linux native
  "$HOME/.config/ModrinthApp/profiles"                               # Linux config-style
  "${APPDATA:-}/ModrinthApp/profiles"                                # Windows (Cygwin/Git Bash)
)

detect_profile() {
  local root name
  for root in "${PROFILES_ROOTS[@]}"; do
    [[ -n "$root" && -d "$root" ]] || continue
    for name in "${PACK_NAMES[@]}"; do
      if [[ -d "$root/$name" ]]; then
        printf '%s' "$root/$name"
        return 0
      fi
    done
  done
  return 1
}

PROFILE="${1:-$(detect_profile || true)}"
if [[ -z "${PROFILE:-}" || ! -d "$PROFILE" ]]; then
  {
    echo "❌ Profil ModrinthApp introuvable."
    echo "   Noms testés : ${PACK_NAMES[*]}"
    echo "   Profils disponibles :"
    for root in "${PROFILES_ROOTS[@]}"; do
      [[ -n "$root" && -d "$root" ]] || continue
      find "$root" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sed 's|^|     - |'
    done
    echo "   Override : $0 /chemin/vers/profile  ou  PACK_NAME=NomDuProfil $0"
  } >&2
  exit 1
fi
echo "📁 Profil : $PROFILE"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "🌐 Téléchargement du pack ($PACK_URL)..."
if ! curl -fsSL "$PACK_URL" -o "$WORK/pack.mrpack"; then
  echo "❌ Échec du téléchargement de $PACK_URL" >&2
  echo "   Vérifier la connectivité au serveur (port 25566 doit être atteignable)." >&2
  exit 1
fi
echo "📦 $(du -h "$WORK/pack.mrpack" | cut -f1)"

PROFILE="$PROFILE" PACK="$WORK/pack.mrpack" python3 - <<'PYEOF'
import hashlib, json, os, shutil, sys, urllib.request, zipfile
from datetime import datetime
from pathlib import Path

profile = Path(os.environ["PROFILE"])
pack = Path(os.environ["PACK"])
ASSET_FOLDERS = ("mods", "resourcepacks", "shaderpacks")

with zipfile.ZipFile(pack) as z:
    manifest = json.loads(z.read("modrinth.index.json"))

    # Fichiers déclarés dans le manifeste (mods Modrinth canoniques)
    expected = {f: {} for f in ASSET_FOLDERS}
    for entry in manifest["files"]:
        path = entry["path"]
        folder, _, fn = path.partition("/")
        if folder not in expected or not fn or "/" in fn:
            continue
        env = entry.get("env", {})
        # Sur un client, on n'installe pas les mods server-only
        if env.get("client") == "unsupported":
            continue
        expected[folder][fn] = {
            "sha1": entry["hashes"]["sha1"],
            "url":  entry["downloads"][0],
        }

    # Fichiers présents dans overrides/ du .mrpack (jars patchés, configs perso)
    overrides_zentries = {f: {} for f in ASSET_FOLDERS}
    for name in z.namelist():
        if not name.startswith("overrides/"):
            continue
        parts = name.split("/", 2)
        if len(parts) < 3 or not parts[2]:
            continue
        folder, fn = parts[1], parts[2]
        if folder in overrides_zentries and "/" not in fn:
            overrides_zentries[folder][fn] = name

    # Compute backup dir lazily
    backup_dir = profile / ".update-backup" / datetime.now().strftime("%Y%m%d-%H%M%S")
    def to_backup(folder, src):
        target = backup_dir / folder
        target.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(target / src.name))

    def sha1_file(p):
        h = hashlib.sha1()
        with p.open("rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 16), b""):
                h.update(chunk)
        return h.hexdigest()

    def sha1_bytes(b):
        return hashlib.sha1(b).hexdigest()

    summary = {"add": 0, "update": 0, "remove": 0, "ok": 0}

    for folder in ASSET_FOLDERS:
        local_dir = profile / folder
        modrinth_files = expected[folder]
        override_zentries = overrides_zentries[folder]
        # Le set "target" final = mods Modrinth + overrides
        target = set(modrinth_files) | set(override_zentries)

        # Skip si pas de présence locale et rien à installer
        if not local_dir.exists() and not target:
            continue
        local_dir.mkdir(parents=True, exist_ok=True)

        local_files = {p.name: p for p in local_dir.iterdir()
                       if p.is_file() and not p.name.startswith(".")}

        # Compute SHA-1 pour les overrides (taille petite, lecture du zip)
        override_sha = {}
        override_data = {}
        for fn, zentry in override_zentries.items():
            data = z.read(zentry)
            override_sha[fn] = sha1_bytes(data)
            override_data[fn] = data

        # 1) Suppressions : fichiers locaux qui ne sont plus dans le pack
        for fn in sorted(set(local_files) - target):
            print(f"  🗑️  remove {folder}/{fn}")
            to_backup(folder, local_files[fn])
            summary["remove"] += 1

        # 2) Ajouts : nouveaux fichiers
        for fn in sorted(target - set(local_files)):
            target_path = local_dir / fn
            if fn in override_zentries:
                target_path.write_bytes(override_data[fn])
                print(f"  ➕ add (override) {folder}/{fn}")
            else:
                req = urllib.request.Request(modrinth_files[fn]["url"],
                                             headers={"User-Agent": "wsl/update-client/1.0"})
                with urllib.request.urlopen(req, timeout=60) as resp, target_path.open("wb") as dst:
                    shutil.copyfileobj(resp, dst)
                print(f"  ➕ add {folder}/{fn}")
            summary["add"] += 1

        # 3) Updates : fichiers présents des deux côtés mais SHA-1 différent
        for fn in sorted(target & set(local_files)):
            local_sha = sha1_file(local_files[fn])
            if fn in override_zentries:
                expected_sha = override_sha[fn]
                if local_sha == expected_sha:
                    summary["ok"] += 1
                    continue
                to_backup(folder, local_files[fn])
                (local_dir / fn).write_bytes(override_data[fn])
                print(f"  🔄 update (override) {folder}/{fn}")
            else:
                expected_sha = modrinth_files[fn]["sha1"]
                if local_sha == expected_sha:
                    summary["ok"] += 1
                    continue
                to_backup(folder, local_files[fn])
                req = urllib.request.Request(modrinth_files[fn]["url"],
                                             headers={"User-Agent": "wsl/update-client/1.0"})
                with urllib.request.urlopen(req, timeout=60) as resp, (local_dir / fn).open("wb") as dst:
                    shutil.copyfileobj(resp, dst)
                print(f"  🔄 update {folder}/{fn}")
            summary["update"] += 1

print(f"\n📊 Résumé : {summary['add']} ajout(s), {summary['update']} update(s), "
      f"{summary['remove']} retiré(s), {summary['ok']} OK.")
if backup_dir.exists():
    print(f"💾 Anciens fichiers déplacés : {backup_dir}")
print(f"\n✅ Update terminée — config/, options.txt, journeymap/, saves/ et autres data préservées.")
PYEOF
