#!/usr/bin/env bash
# sync-pack.sh — Build, upload, and deploy a Modrinth modpack in one shot.
# Source de vérité : la Modrinth App locale (Kubuntu).
# Cible : projet Modrinth (unlisted) + cluster Docker `minecraft-server` (via `da`).

set -euo pipefail

# ─── Configuration (override via env, sinon valeurs par défaut) ──────────────
: "${PACK_NAME:=CoupaingCraft}"               # Nom du dossier de profil dans ModrinthApp
: "${PACK_DISPLAY_NAME:=coupaing-craft}"      # Nom utilisé dans le manifest .mrpack (≠ nom du dossier)
: "${MODRINTH_PROJECT_ID:=4fBwVYft}"          # Modrinth dashboard ⋮ → Copy ID
: "${MODRINTH_PROJECT_SLUG:=coupaing-craft}"  # Pour affichage / liens
: "${GAME_VERSION:=1.21.11}"                  # Version Minecraft (cohérent avec config/.env)
: "${LOADER:=fabric}"                         # fabric / forge / neoforge / quilt
: "${LOADER_VERSION:=0.19.2}"                 # Version du loader (cohérent avec config/.env)
: "${SERVER_ONLY_PROJECTS:=c2me-fabric,krypton,dynmap}"  # Forcer env={client:unsupported, server:required}
: "${MODRINTH_PROFILE_DIR:=}"                 # Override du chemin du profil (auto-détecté si vide)
: "${USER_AGENT:=wsl/sync-pack/1.0 (kubuntu-homelab)}"
: "${TOKEN_FILE:=$HOME/.config/sync-pack/token}"
: "${SECRET_TOOL_SERVICE:=modrinth-pat}"

CLUSTER_NAME="minecraft-server"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Flags ───────────────────────────────────────────────────────────────────
DRY_RUN=0; NO_UPLOAD=0; NO_DEPLOY=0
CHANGELOG=""

usage() {
  cat <<EOF
Usage: ./sync-pack.sh [--dry-run|--no-upload|--no-deploy] [changelog]

Sans flag : build → upload Modrinth → da restart minecraft-server.

Flags :
  --dry-run     Build le .mrpack puis stop (palier A). Implique --no-upload + --no-deploy.
  --no-upload   Build seulement, pas d'upload (implique --no-deploy).
  --no-deploy   Build + upload, pas de da restart (palier B).
  -h, --help    Cette aide.

Variables d'environnement utiles (override des valeurs par défaut en tête de script) :
  PACK_NAME=<NomDuDossierProfil>          (default: pack)
  PACK_DISPLAY_NAME=<NomAffichéManifest>  (default: coupaing-craft)
  MODRINTH_PROJECT_ID=<ID-du-projet-Modrinth>
  MODRINTH_PROFILE_DIR=<chemin-explicite>
  GAME_VERSION=1.21.11   LOADER=fabric   LOADER_VERSION=0.19.2

PAT Modrinth lu en série : secret-tool (service=$SECRET_TOOL_SERVICE) → $TOKEN_FILE → \$MODRINTH_TOKEN.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=1; NO_UPLOAD=1; NO_DEPLOY=1; shift ;;
    --no-upload) NO_UPLOAD=1; NO_DEPLOY=1; shift ;;
    --no-deploy) NO_DEPLOY=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "❌ Flag inconnu : $1" >&2; usage >&2; exit 2 ;;
    *)           CHANGELOG="$1"; shift ;;
  esac
done

[[ -n "$CHANGELOG" ]] || CHANGELOG="Mise à jour automatique"

# ─── Auto-détection du profil ModrinthApp ────────────────────────────────────
detect_profile() {
  if [[ -n "$MODRINTH_PROFILE_DIR" ]]; then
    [[ -d "$MODRINTH_PROFILE_DIR" ]] || {
      echo "❌ MODRINTH_PROFILE_DIR=$MODRINTH_PROFILE_DIR n'existe pas." >&2
      exit 1
    }
    printf '%s' "$MODRINTH_PROFILE_DIR"
    return
  fi

  local candidates=(
    "$HOME/.config/com.modrinth.theseus/profiles/$PACK_NAME"
    "$HOME/.local/share/com.modrinth.theseus/profiles/$PACK_NAME"
    "$HOME/.var/app/com.modrinth.theseus/config/com.modrinth.theseus/profiles/$PACK_NAME"
    "$HOME/.config/ModrinthApp/profiles/$PACK_NAME"
    "$HOME/.local/share/ModrinthApp/profiles/$PACK_NAME"
  )
  local found=()
  local c
  for c in "${candidates[@]}"; do
    [[ -d "$c" ]] && found+=("$c")
  done

  case ${#found[@]} in
    0)
      {
        echo "❌ Aucun profil ModrinthApp trouvé pour PACK_NAME='$PACK_NAME'."
        echo "   Cherché dans :"
        printf '     - %s\n' "${candidates[@]}"
        echo "   Profils existants détectés :"
        local base
        for base in \
          "$HOME/.config/com.modrinth.theseus/profiles" \
          "$HOME/.local/share/com.modrinth.theseus/profiles" \
          "$HOME/.var/app/com.modrinth.theseus/config/com.modrinth.theseus/profiles" \
          "$HOME/.config/ModrinthApp/profiles" \
          "$HOME/.local/share/ModrinthApp/profiles"
        do
          if [[ -d "$base" ]]; then
            find "$base" -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
              | sed 's|^|     - |'
          fi
        done
        echo "   Override : MODRINTH_PROFILE_DIR=/chemin/du/profil ./sync-pack.sh ..."
      } >&2
      exit 1
      ;;
    1)
      printf '%s' "${found[0]}"
      ;;
    *)
      {
        echo "❌ Plusieurs profils correspondent à PACK_NAME='$PACK_NAME' :"
        printf '     - %s\n' "${found[@]}"
        echo "   Désambiguïser via MODRINTH_PROFILE_DIR=..."
      } >&2
      exit 1
      ;;
  esac
}

# ─── Récupération du PAT (skippé en --no-upload) ─────────────────────────────
get_token() {
  if command -v secret-tool >/dev/null 2>&1; then
    local t
    t="$(secret-tool lookup service "$SECRET_TOOL_SERVICE" user "$USER" 2>/dev/null || true)"
    if [[ -n "$t" ]]; then
      printf '%s' "$t"
      return 0
    fi
  fi
  if [[ -f "$TOKEN_FILE" ]]; then
    local t
    t="$(cat "$TOKEN_FILE")"
    if [[ -n "$t" ]]; then
      printf '%s' "$t"
      return 0
    fi
  fi
  if [[ -n "${MODRINTH_TOKEN:-}" ]]; then
    printf '%s' "$MODRINTH_TOKEN"
    return 0
  fi
  return 1
}

# ─── Pré-vols ────────────────────────────────────────────────────────────────
PROFILE_DIR="$(detect_profile)"
echo "📁 Profil ModrinthApp : $PROFILE_DIR"

TOKEN=""
if [[ "$NO_UPLOAD" -eq 0 ]]; then
  if ! TOKEN="$(get_token)"; then
    {
      echo "❌ PAT Modrinth introuvable."
      echo "   Sources tentées :"
      echo "     - secret-tool lookup service $SECRET_TOOL_SERVICE user \$USER"
      echo "     - $TOKEN_FILE"
      echo "     - \$MODRINTH_TOKEN"
      echo "   Stocker via : secret-tool store --label='Modrinth PAT' service $SECRET_TOOL_SERVICE user \"\$USER\""
    } >&2
    exit 1
  fi
  if [[ -z "$MODRINTH_PROJECT_ID" ]]; then
    echo "❌ MODRINTH_PROJECT_ID manquant. Récupérable via Modrinth dashboard → ⋮ → Copy ID." >&2
    exit 1
  fi
fi

VERSION_NUMBER="$(date +%Y.%m.%d-%H%M)"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ "$DRY_RUN" -eq 1 ]]; then
  MRPACK_PATH="$SCRIPT_DIR/dry-run-pack.mrpack"
else
  MRPACK_PATH="$WORK_DIR/pack.mrpack"
fi

# ─── Build du .mrpack via Python ─────────────────────────────────────────────
PROFILE_DIR="$PROFILE_DIR" \
GAME_VERSION="$GAME_VERSION" \
LOADER="$LOADER" \
LOADER_VERSION="$LOADER_VERSION" \
SERVER_ONLY_PROJECTS="$SERVER_ONLY_PROJECTS" \
MRPACK_PATH="$MRPACK_PATH" \
PACK_VERSION="$VERSION_NUMBER" \
PACK_DISPLAY_NAME="$PACK_DISPLAY_NAME" \
USER_AGENT="$USER_AGENT" \
python3 - <<'PYEOF'
import hashlib, json, os, sys, urllib.request, urllib.error, zipfile
from collections import defaultdict
from pathlib import Path

profile        = Path(os.environ["PROFILE_DIR"])
game_version   = os.environ["GAME_VERSION"]
loader         = os.environ["LOADER"]
loader_version = os.environ.get("LOADER_VERSION") or ""
mrpack_path    = Path(os.environ["MRPACK_PATH"])
pack_version   = os.environ["PACK_VERSION"]
display_name   = os.environ.get("PACK_DISPLAY_NAME") or profile.name
ua             = os.environ["USER_AGENT"]
server_only    = {s.strip() for s in os.environ.get("SERVER_ONLY_PROJECTS", "").split(",") if s.strip()}

mods_dir = profile / "mods"
if not mods_dir.is_dir():
    sys.exit(f"❌ Pas de dossier mods/ dans {profile}")

def hashes(path):
    sha1, sha512, size = hashlib.sha1(), hashlib.sha512(), 0
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            sha1.update(chunk); sha512.update(chunk); size += len(chunk)
    return sha1.hexdigest(), sha512.hexdigest(), size

def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": ua})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise

jars = sorted(mods_dir.glob("*.jar"))
if not jars:
    sys.exit(f"❌ Aucun .jar dans {mods_dir}")

disabled = sorted(mods_dir.glob("*.jar.disabled"))
if disabled:
    print(f"  ⏸️  {len(disabled)} mod(s) désactivé(s) (ignorés) :")
    for d in disabled:
        print(f"       - {d.name}")

files, overrides_jars = [], []
seen_projects = defaultdict(list)

for jar in jars:
    sha1, _, _ = hashes(jar)
    print(f"  🔍 {jar.name}", flush=True)

    version_info = fetch_json(f"https://api.modrinth.com/v2/version_file/{sha1}?algorithm=sha1")
    if version_info is None:
        print( "    ⚠️  Pas sur Modrinth → overrides/")
        overrides_jars.append(jar)
        continue

    project_id = version_info["project_id"]
    project    = fetch_json(f"https://api.modrinth.com/v2/project/{project_id}") or {}
    slug       = project.get("slug") or project_id
    seen_projects[project_id].append((jar.name, slug))

    server_side = project.get("server_side", "required")
    client_side = project.get("client_side", "required")
    env = {
        "client": "required" if client_side != "unsupported" else "unsupported",
        "server": "required" if server_side != "unsupported" else "unsupported",
    }
    if client_side == "optional": env["client"] = "optional"
    if server_side == "optional": env["server"] = "optional"

    if slug in server_only or project_id in server_only:
        env = {"client": "unsupported", "server": "required"}
        print(f"    🛡️  forced server-only ({slug})")

    primary = next((f for f in version_info["files"] if f.get("primary")), version_info["files"][0])
    files.append({
        "path": f"mods/{jar.name}",
        "hashes": {"sha1": primary["hashes"]["sha1"], "sha512": primary["hashes"]["sha512"]},
        "env": env,
        "downloads": [primary["url"]],
        "fileSize": primary["size"],
    })

dupes = {pid: items for pid, items in seen_projects.items() if len(items) > 1}
if dupes:
    print("❌ Doublons de mods (deux versions du même project_id) :", file=sys.stderr)
    for pid, items in dupes.items():
        slug = items[0][1]
        for jar_name, _ in items:
            print(f"     - {slug}: {jar_name}", file=sys.stderr)
    sys.exit(1)

loader_key = {"fabric": "fabric-loader", "forge": "forge",
              "neoforge": "neoforge", "quilt": "quilt-loader"}[loader]
deps = {"minecraft": game_version}
if loader_version:
    deps[loader_key] = loader_version

manifest = {
    "formatVersion": 1, "game": "minecraft", "versionId": pack_version,
    "name": display_name, "summary": f"Auto-export {pack_version}",
    "files": files, "dependencies": deps,
}

mrpack_path.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(mrpack_path, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("modrinth.index.json", json.dumps(manifest, indent=2))
    for jar in overrides_jars:
        z.write(jar, f"overrides/mods/{jar.name}")
    config_dir = profile / "config"
    if config_dir.is_dir():
        for f in config_dir.rglob("*"):
            if f.is_file():
                z.write(f, f"overrides/config/{f.relative_to(config_dir)}")

print(f"✅ {len(files)} mod(s) Modrinth, {len(overrides_jars)} en overrides → {mrpack_path}")
PYEOF

echo ""
echo "📦 Pack généré : $MRPACK_PATH ($(du -h "$MRPACK_PATH" | cut -f1))"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  echo "🛑 --dry-run : arrêt après build."
  echo "   Inspecter :   unzip -p '$MRPACK_PATH' modrinth.index.json | jq"
  echo "   Tester import : ouvrir le .mrpack dans une autre instance ModrinthApp."
  exit 0
fi

if [[ "$NO_UPLOAD" -eq 1 ]]; then
  # Le pack vit dans WORK_DIR et sera nettoyé par le trap. Le copier pour conservation.
  KEEP_PATH="$SCRIPT_DIR/last-pack.mrpack"
  cp "$MRPACK_PATH" "$KEEP_PATH"
  echo "🛑 --no-upload : skip API Modrinth."
  echo "   Pack conservé : $KEEP_PATH"
  exit 0
fi

# ─── Upload Modrinth ─────────────────────────────────────────────────────────
echo ""
echo "☁️  Upload sur Modrinth (project_id=$MODRINTH_PROJECT_ID)..."

UPLOAD_DATA="$(VERSION="$VERSION_NUMBER" \
                CHANGELOG="$CHANGELOG" \
                GAME_VERSION="$GAME_VERSION" \
                LOADER="$LOADER" \
                MODRINTH_PROJECT_ID="$MODRINTH_PROJECT_ID" \
  python3 - <<'PY'
import json, os
print(json.dumps({
    "name":           f"Auto-build {os.environ['VERSION']}",
    "version_number": os.environ["VERSION"],
    "changelog":      os.environ["CHANGELOG"],
    "dependencies":   [],
    "game_versions":  [os.environ["GAME_VERSION"]],
    "version_type":   "release",
    "loaders":        [os.environ["LOADER"]],
    "featured":       False,
    "project_id":     os.environ["MODRINTH_PROJECT_ID"],
    "file_parts":     ["pack"],
}))
PY
)"

RESPONSE_FILE="$WORK_DIR/upload-response.json"
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w "%{http_code}" \
    -X POST "https://api.modrinth.com/v2/version" \
    -H "Authorization: $TOKEN" \
    -H "User-Agent: $USER_AGENT" \
    -F "data=$UPLOAD_DATA;type=application/json" \
    -F "pack=@$MRPACK_PATH;type=application/x-modrinth-modpack+zip")"

if [[ "$HTTP_CODE" != "200" ]]; then
  {
    echo "❌ Upload échoué (HTTP $HTTP_CODE)"
    cat "$RESPONSE_FILE" 2>/dev/null
    echo ""
    case "$HTTP_CODE" in
      400) echo "   Hint : version_number en doublon ? PROJECT_ID inexistant ? Manifest invalide ?" ;;
      401) echo "   Hint : PAT invalide ou révoqué." ;;
      403) echo "   Hint : PAT ne possède pas le scope 'Create versions'." ;;
      404) echo "   Hint : MODRINTH_PROJECT_ID introuvable." ;;
      429) echo "   Hint : rate limit Modrinth (300 req/min). Réessayer dans 1 min." ;;
    esac
  } >&2
  exit 1
fi

echo "✅ Version uploadée : $VERSION_NUMBER"

if [[ "$NO_DEPLOY" -eq 1 ]]; then
  echo "🛑 --no-deploy : skip déploiement local."
  exit 0
fi

# ─── Deploy local via `da restart` ───────────────────────────────────────────
echo ""
echo "🚀 Déploiement local (da restart $CLUSTER_NAME)..."

cd "$REPO_ROOT"
# shellcheck disable=SC1091
source "./.bash_utils"
da restart "$CLUSTER_NAME"

echo ""
echo "✅ Sync terminée."
echo "   Logs serveur  :  cd $REPO_ROOT && source .bash_utils && da logs $CLUSTER_NAME"
echo "   Logs watcher  :  tail -f $REPO_ROOT/$CLUSTER_NAME/shared/dynmap-auto-render.log"
