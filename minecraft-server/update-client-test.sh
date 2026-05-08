#!/usr/bin/env bash
# =============================================================================
# update-client-test.sh — Variante de update-client.sh pour le cluster TEST.
#
# Met à jour le profil ModrinthApp dédié au serveur test (parallèle au profil
# de prod). Touche UNIQUEMENT mods/, resourcepacks/, shaderpacks/, datapacks/.
# Configs/saves/journeymap data préservées.
#
# Usage :
#   ./update-pack-test.sh                # auto-détecte le profil test
#   ./update-pack-test.sh /chemin/profil # path explicite
#
# Variables d'env :
#   PACK_URL   URL du .mrpack
#              (default: http://90.79.99.178:25566/coupaing-craft.mrpack
#               — actuellement le test partage le pack de prod via copie auto
#               au pre-up.sh côté serveur ; URL identique à update-client.sh.)
#   PACK_NAME  Nom du dossier de profil ModrinthApp à viser
#              (override la liste de candidats par défaut).
# =============================================================================
set -euo pipefail

PACK_URL="${PACK_URL:-http://90.79.99.178:25566/coupaing-craft-test.mrpack}"
PACK_NAMES_DEFAULT=("coupaing-craft-test" "CoupaingCraft-Test" "pack-test" "test" "coupaing-craft (test)")
if [[ -n "${PACK_NAME:-}" ]]; then
  PACK_NAMES=("$PACK_NAME")
else
  PACK_NAMES=("${PACK_NAMES_DEFAULT[@]}")
fi

PROFILES_ROOTS=(
  "$HOME/.var/app/com.modrinth.ModrinthApp/data/ModrinthApp/profiles"  # Flatpak nouveau (SteamDeck/Linux)
  "$HOME/.var/app/com.modrinth.theseus/data/ModrinthApp/profiles"      # Flatpak ancien Theseus
  "$HOME/.local/share/ModrinthApp/profiles"                              # Linux native
  "$HOME/.config/ModrinthApp/profiles"                                   # Linux config-style
  "${APPDATA:-}/ModrinthApp/profiles"                                    # Windows (Cygwin/Git Bash)
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
    echo "❌ Profil ModrinthApp test introuvable."
    echo "   Noms testés : ${PACK_NAMES[*]}"
    echo "   Profils disponibles :"
    for root in "${PROFILES_ROOTS[@]}"; do
      [[ -n "$root" && -d "$root" ]] || continue
      find "$root" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sed 's|^|     - |'
    done
    echo ""
    echo "   Crée un profil dédié au test dans ModrinthApp (ex: nom 'coupaing-craft-test',"
    echo "   importé from-file ou cloné depuis le profil prod), puis relance."
    echo "   Override : $0 /chemin/vers/profile  ou  PACK_NAME=NomDuProfil $0"
  } >&2
  exit 1
fi
echo "📁 Profil test : $PROFILE"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "🌐 Téléchargement du pack ($PACK_URL)..."
if ! curl -fsSL "$PACK_URL" -o "$WORK/pack.mrpack"; then
  echo "❌ Échec du téléchargement de $PACK_URL" >&2
  echo "   Vérifier que le serveur Dynmap (port 25566) est accessible." >&2
  exit 1
fi
echo "📦 $(du -h "$WORK/pack.mrpack" | cut -f1)"

PROFILE="$PROFILE" PACK="$WORK/pack.mrpack" python3 - <<'PYEOF'
import hashlib, json, os, shutil, sys, urllib.request, zipfile
from datetime import datetime
from pathlib import Path

profile = Path(os.environ["PROFILE"])
pack = Path(os.environ["PACK"])
ASSET_FOLDERS = ("mods", "resourcepacks", "shaderpacks", "datapacks")

with zipfile.ZipFile(pack) as z:
    manifest = json.loads(z.read("modrinth.index.json"))

    expected = {f: {} for f in ASSET_FOLDERS}
    for entry in manifest["files"]:
        path = entry["path"]
        folder, _, fn = path.partition("/")
        if folder not in expected or not fn or "/" in fn:
            continue
        env = entry.get("env", {})
        if env.get("client") == "unsupported":
            continue
        expected[folder][fn] = {
            "sha1": entry["hashes"]["sha1"],
            "url":  entry["downloads"][0],
        }

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
        target = set(modrinth_files) | set(override_zentries)

        if not local_dir.exists() and not target:
            continue
        local_dir.mkdir(parents=True, exist_ok=True)

        local_files = {p.name: p for p in local_dir.iterdir()
                       if p.is_file() and not p.name.startswith(".")}

        override_sha = {}
        override_data = {}
        for fn, zentry in override_zentries.items():
            data = z.read(zentry)
            override_sha[fn] = sha1_bytes(data)
            override_data[fn] = data

        for fn in sorted(set(local_files) - target):
            print(f"  🗑️  remove {folder}/{fn}")
            to_backup(folder, local_files[fn])
            summary["remove"] += 1

        for fn in sorted(target - set(local_files)):
            target_path = local_dir / fn
            if fn in override_zentries:
                target_path.write_bytes(override_data[fn])
                print(f"  ➕ add (override) {folder}/{fn}")
            else:
                req = urllib.request.Request(modrinth_files[fn]["url"],
                                             headers={"User-Agent": "wsl/update-client-test/1.0"})
                with urllib.request.urlopen(req, timeout=60) as resp, target_path.open("wb") as dst:
                    shutil.copyfileobj(resp, dst)
                print(f"  ➕ add {folder}/{fn}")
            summary["add"] += 1

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
                                             headers={"User-Agent": "wsl/update-client-test/1.0"})
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
