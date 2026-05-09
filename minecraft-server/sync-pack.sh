#!/usr/bin/env bash
# sync-pack.sh — Build, upload, and deploy a Modrinth modpack in one shot.
# Source de vérité : la Modrinth App locale (Kubuntu).
# Cible : projet Modrinth (unlisted) + cluster Docker `minecraft-server` (via `da`).

set -euo pipefail

# Lire VERSION + FABRIC_LOADER_VERSION depuis config/.env AVANT les defaults
# pour éviter la dérive entre le .env serveur et le manifest .mrpack uploadé.
_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_self_dir/config/.env" ]; then
    _ev=$(grep -E '^\s*VERSION\s*=' "$_self_dir/config/.env" | head -1 | cut -d= -f2- | tr -d '"' | xargs)
    _el=$(grep -E '^\s*FABRIC_LOADER_VERSION\s*=' "$_self_dir/config/.env" | head -1 | cut -d= -f2- | tr -d '"' | xargs)
    [ -n "${_ev:-}" ] && [ -z "${GAME_VERSION:-}" ] && GAME_VERSION="$_ev"
    [ -n "${_el:-}" ] && [ -z "${LOADER_VERSION:-}" ] && LOADER_VERSION="$_el"
fi

# ─── Configuration (override via env, sinon valeurs par défaut) ──────────────
: "${PACK_NAME:=CoupaingCraft-Master}"        # Nom du dossier de profil dans ModrinthApp (profil maître, source de vérité, unlinked du pack)
: "${PACK_DISPLAY_NAME:=coupaing-craft}"      # Nom utilisé dans le manifest .mrpack (≠ nom du dossier)
: "${MODRINTH_PROJECT_ID:=4fBwVYft}"          # Modrinth dashboard ⋮ → Copy ID
: "${MODRINTH_PROJECT_SLUG:=coupaing-craft}"  # Pour affichage / liens
: "${GAME_VERSION:=1.21.11}"                  # Version Minecraft (cohérent avec config/.env)
: "${LOADER:=fabric}"                         # fabric / forge / neoforge / quilt
: "${LOADER_VERSION:=0.19.2}"                 # Version du loader (cohérent avec config/.env)
: "${SERVER_ONLY_PROJECTS:=c2me-fabric,krypton,dynmap}"  # Forcer env={client:unsupported, server:required}
: "${CLIENT_REQUIRED_PROJECTS:=lithostitched,create-peaceful,harvest-enchantment,create_oxidized,create-pattern-schematics,when-dungeons-arise,ct-overhaul-village}"  # Forcer env={client:required, server:required} — pour les mods tagués client:unsupported sur Modrinth mais en réalité requis côté client (worldgen, registry partagé, ou advancement assets/textures cassés sans le mod côté client)
: "${MODRINTH_PROFILE_DIR:=}"                 # Override du chemin du profil (auto-détecté si vide)
: "${USER_AGENT:=wsl/sync-pack/1.0 (kubuntu-homelab)}"
: "${TOKEN_FILE:=$HOME/.config/sync-pack/token}"
: "${SECRET_TOOL_SERVICE:=modrinth-pat}"

CLUSTER_NAME="minecraft-server"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Flags ───────────────────────────────────────────────────────────────────
DRY_RUN=0; NO_UPLOAD=0; NO_DEPLOY=0; BUILD_TEST_PACK=0
CHANGELOG=""

usage() {
  cat <<EOF
Usage: ./sync-pack.sh [--dry-run|--no-upload|--no-deploy|--test] [changelog]

Sans flag : build (mods/) → upload Modrinth → da restart minecraft-server.

Flags :
  --dry-run     Build le .mrpack puis stop (palier A). Implique --no-upload + --no-deploy.
  --no-upload   Build seulement, pas d'upload (implique --no-deploy).
  --no-deploy   Build + upload, pas de da restart (palier B).
  --test        Build d'un PACK TEST séparé incluant aussi <profil>/mods-test-only/.
                Sortie : shared/data/coupaing-craft-test.mrpack + dynmap/web/coupaing-craft-test.mrpack.
                N'upload PAS sur Modrinth, ne touche PAS au pack prod ni à coupaing-craft-initial.mrpack.
                Workflow : itérer en test → quand validé, déplacer mods-test-only/<jar> vers
                mods/ et faire ./sync-pack.sh "promote <jar>" pour pousser en prod.
  -h, --help    Cette aide.

Variables d'environnement utiles (override des valeurs par défaut en tête de script) :
  PACK_NAME=<NomDuDossierProfil>          (default: CoupaingCraft-Master)
  PACK_DISPLAY_NAME=<NomAffichéManifest>  (default: coupaing-craft)
  MODRINTH_PROJECT_ID=<ID-du-projet-Modrinth>
  MODRINTH_PROFILE_DIR=<chemin-explicite>
  GAME_VERSION=1.20.1   LOADER=fabric   LOADER_VERSION=0.19.2

PAT Modrinth lu en série : secret-tool (service=$SECRET_TOOL_SERVICE) → $TOKEN_FILE → \$MODRINTH_TOKEN.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=1; NO_UPLOAD=1; NO_DEPLOY=1; shift ;;
    --no-upload) NO_UPLOAD=1; NO_DEPLOY=1; shift ;;
    --no-deploy) NO_DEPLOY=1; shift ;;
    --test)      BUILD_TEST_PACK=1; NO_UPLOAD=1; NO_DEPLOY=1; shift ;;
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

# ─── Auto-build des resource packs maison ───────────────────────────────────
# Sources raw versionnées dans <repo>/minecraft-server/resourcepacks/<name>/
# → zippées dans <master>/resourcepacks/<name>.zip (idempotent : régénère
# uniquement si une source est plus récente que le zip).
RP_SRC_DIR="$SCRIPT_DIR/resourcepacks"
if [[ -d "$RP_SRC_DIR" ]]; then
    RP_DST_DIR="$PROFILE_DIR/resourcepacks"
    mkdir -p "$RP_DST_DIR"
    for src in "$RP_SRC_DIR"/*/; do
        [[ -d "$src" ]] || continue
        rp_name="$(basename "$src")"
        rp_zip="$RP_DST_DIR/${rp_name}.zip"
        if [[ ! -f "$rp_zip" ]] || find "$src" -newer "$rp_zip" -print -quit 2>/dev/null | grep -q .; then
            (cd "$src" && zip -qr "$rp_zip" . -x "*.swp" -x ".DS_Store")
            echo "  📦 Resource pack régénéré : $rp_name.zip"
        fi
    done
fi

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
TEST_DISPLAY_NAME="${PACK_DISPLAY_NAME}-test"
BUILD_DISPLAY_NAME="$PACK_DISPLAY_NAME"
[[ "$BUILD_TEST_PACK" -eq 1 ]] && BUILD_DISPLAY_NAME="$TEST_DISPLAY_NAME"

PROFILE_DIR="$PROFILE_DIR" \
GAME_VERSION="$GAME_VERSION" \
LOADER="$LOADER" \
LOADER_VERSION="$LOADER_VERSION" \
SERVER_ONLY_PROJECTS="$SERVER_ONLY_PROJECTS" \
CLIENT_REQUIRED_PROJECTS="$CLIENT_REQUIRED_PROJECTS" \
MRPACK_PATH="$MRPACK_PATH" \
PACK_VERSION="$VERSION_NUMBER" \
PACK_DISPLAY_NAME="$BUILD_DISPLAY_NAME" \
BUILD_TEST_PACK="$BUILD_TEST_PACK" \
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
client_required = {s.strip() for s in os.environ.get("CLIENT_REQUIRED_PROJECTS", "").split(",") if s.strip()}

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

# Types d'assets scannés dans le profil (en plus de overrides/config/).
# `fallback_env=None` → utilise la métadata Modrinth (client_side/server_side) du projet.
# Pour les autres dossiers, l'env est forcé.
#
# Note datapacks : ModrinthApp les extrait dans <profile>/datapacks/ — utile en
# solo (auto-appliqués aux nouveaux mondes selon launcher). Pour le serveur
# multijoueur, les datapacks vivent dans shared/data/world/datapacks/ — déposer
# directement là, pas via le pack. Default env=optional/optional pour rester
# flexible ; override possible par mod via SERVER_ONLY_PROJECTS / CLIENT_REQUIRED_PROJECTS
# si le datapack est listé sur Modrinth.
# Tuple : (scan_folder, glob, fallback_env, manifest_folder).
# manifest_folder = chemin dans le .mrpack (différent de scan_folder pour
# mods-test-only/ → mappé vers mods/ pour qu'ModrinthApp les installe au bon endroit).
ASSET_TYPES = [
    ("mods",          "*.jar", None,                                            "mods"),
    ("resourcepacks", "*.zip", {"client": "required",   "server": "unsupported"}, "resourcepacks"),
    ("shaderpacks",   "*.zip", {"client": "optional",   "server": "unsupported"}, "shaderpacks"),
    ("datapacks",     "*.zip", {"client": "optional",   "server": "optional"},   "datapacks"),
]
# En mode test : on inclut aussi mods-test-only/ (extras non-mergés en prod) en
# les mappant vers mods/ dans le manifest.
if os.environ.get("BUILD_TEST_PACK") == "1":
    ASSET_TYPES.append(("mods-test-only", "*.jar", None, "mods"))
    print("🧪 Mode TEST : scanne aussi mods-test-only/")

files, overrides = [], []  # overrides : liste de (Path source, str path-in-zip)
seen_projects = defaultdict(list)
total_assets = 0

for folder, glob_pat, fallback_env, manifest_folder in ASSET_TYPES:
    asset_dir = profile / folder
    if not asset_dir.is_dir():
        continue
    items = sorted(asset_dir.glob(glob_pat))
    if not items:
        continue

    # Détection des assets désactivés (ModrinthApp suffixe .disabled).
    if folder == "mods":
        disabled = sorted(asset_dir.glob("*.jar.disabled"))
        if disabled:
            print(f"  ⏸️  {len(disabled)} mod(s) désactivé(s) (ignorés) :")
            for d in disabled:
                print(f"       - {d.name}")

    for item in items:
        sha1, _, _ = hashes(item)
        print(f"  🔍 {folder}/{item.name}", flush=True)
        total_assets += 1

        version_info = fetch_json(f"https://api.modrinth.com/v2/version_file/{sha1}?algorithm=sha1")
        if version_info is None:
            print( "    ⚠️  Pas sur Modrinth → overrides/")
            overrides.append((item, f"overrides/{manifest_folder}/{item.name}"))
            continue

        project_id = version_info["project_id"]
        project    = fetch_json(f"https://api.modrinth.com/v2/project/{project_id}") or {}
        slug       = project.get("slug") or project_id
        seen_projects[project_id].append((item.name, slug))

        if fallback_env is not None:
            env = dict(fallback_env)
        else:
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
            elif slug in client_required or project_id in client_required:
                env = {"client": "required", "server": "required"}
                print(f"    📌 forced client-required ({slug})")

        primary = next((f for f in version_info["files"] if f.get("primary")), version_info["files"][0])
        files.append({
            "path": f"{manifest_folder}/{item.name}",
            "hashes": {"sha1": primary["hashes"]["sha1"], "sha512": primary["hashes"]["sha512"]},
            "env": env,
            "downloads": [primary["url"]],
            "fileSize": primary["size"],
        })

if total_assets == 0:
    sys.exit(f"❌ Aucun asset (mods/, resourcepacks/, shaderpacks/) dans {profile}")

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
    for src, target in overrides:
        z.write(src, target)

    # Le master profile contient les configs perso du mainteneur. ON NE LES EMBARQUE
    # PAS dans overrides/config/ : ModrinthApp ré-extrait overrides/ à chaque update,
    # ce qui écraserait les tweaks des joueurs. YOSBR (présent dans le pack) protège
    # options.txt et quelques autres files, mais pas les configs de mods.
    # → Fresh install : mods génèrent leurs configs par défaut (sain).
    # → Update : configs joueur préservées.
    #
    # Pour shipper des defaults pack-spécifiques (ex: presets dynmap, JEI bookmarks),
    # poser les fichiers dans `<profile>/pack-overrides/` du master profile : leur
    # contenu est embarqué tel quel dans overrides/ du .mrpack (sans préfixe
    # config/).
    pack_overrides = profile / "pack-overrides"
    if pack_overrides.is_dir():
        n = 0
        for f in pack_overrides.rglob("*"):
            if f.is_file():
                z.write(f, f"overrides/{f.relative_to(pack_overrides)}")
                n += 1
        if n:
            print(f"  📋 {n} fichier(s) custom embarqué(s) depuis pack-overrides/")

# Décompte par dossier pour le résumé final.
breakdown = defaultdict(int)
for f in files:
    breakdown[f["path"].split("/", 1)[0]] += 1
for _, target in overrides:
    parts = target.split("/", 2)
    if len(parts) >= 2 and parts[0] == "overrides":
        breakdown[f"overrides/{parts[1]}"] += 1
detail = ", ".join(f"{n} {k}" for k, n in sorted(breakdown.items()))
print(f"✅ {len(files)} asset(s) Modrinth, {len(overrides)} en overrides → {mrpack_path}")
print(f"   Détail : {detail}")
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

# ─── Distribution locale du pack (hors --dry-run) ───────────────────────────
# Mode TEST :
#   Pack écrit en parallèle de la prod, NE TOUCHE PAS au pack prod ni à Modrinth.
#     - shared/data/coupaing-craft-test.mrpack          (lu par minecraft-test)
#     - shared/data/dynmap/web/coupaing-craft-test.mrpack (HTTP pour update-client-test.sh)
#   Plus update-client-test.sh exposé via Dynmap.
#
# Mode PROD (défaut) :
#   Distribue aux deux endroits attendus :
#     - shared/data/coupaing-craft-initial.mrpack       (lu par minecraft-server, fallback Under review)
#     - shared/data/dynmap/web/coupaing-craft.mrpack    (HTTP pour update-client.sh)
#   Plus les deux update-client*.sh exposés via Dynmap.
KEEP_PATH="$SCRIPT_DIR/last-pack.mrpack"
cp "$MRPACK_PATH" "$KEEP_PATH"
WEB_DIR="$REPO_ROOT/$CLUSTER_NAME/shared/data/dynmap/web"
mkdir -p "$WEB_DIR"

# Toujours republier les scripts update-client*.sh (utiles dans tous les modes)
[[ -x "$SCRIPT_DIR/update-client.sh"      ]] && cp "$SCRIPT_DIR/update-client.sh"      "$WEB_DIR/update-client.sh"
[[ -x "$SCRIPT_DIR/update-client-test.sh" ]] && cp "$SCRIPT_DIR/update-client-test.sh" "$WEB_DIR/update-client-test.sh"

if [[ "$BUILD_TEST_PACK" -eq 1 ]]; then
  TEST_PACK_LOCAL="$REPO_ROOT/$CLUSTER_NAME/shared/data/coupaing-craft-test.mrpack"
  TEST_PACK_HTTP="$WEB_DIR/coupaing-craft-test.mrpack"
  cp "$MRPACK_PATH" "$TEST_PACK_LOCAL"
  cp "$MRPACK_PATH" "$TEST_PACK_HTTP"
  echo "🧪 Test pack écrit (NE TOUCHE PAS À LA PROD) :"
  echo "    Fallback test cluster : $TEST_PACK_LOCAL"
  echo "    Distribution clients  : $TEST_PACK_HTTP"
  echo ""
  echo "Suite : ./da restart minecraft-test  (côté serveur)"
  echo "        ~/update-client-test.sh      (côté client)"
  exit 0
fi

PACK_LOCAL="$REPO_ROOT/$CLUSTER_NAME/shared/data/coupaing-craft-initial.mrpack"
PACK_HTTP="$WEB_DIR/coupaing-craft.mrpack"
cp "$MRPACK_PATH" "$PACK_LOCAL"
cp "$MRPACK_PATH" "$PACK_HTTP"
echo "📂 Fallback serveur     : $PACK_LOCAL"
echo "🌐 Distribution clients : $PACK_HTTP"
echo "🔧 Scripts update       : $WEB_DIR/update-client*.sh"

if [[ "$NO_UPLOAD" -eq 1 ]]; then
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
                VERSION_TYPE="${VERSION_TYPE:-beta}" \
  python3 - <<'PY'
import json, os
print(json.dumps({
    "name":           f"Auto-build {os.environ['VERSION']}",
    "version_number": os.environ["VERSION"],
    "changelog":      os.environ["CHANGELOG"],
    "dependencies":   [],
    "game_versions":  [os.environ["GAME_VERSION"]],
    "version_type":   os.environ.get("VERSION_TYPE", "beta"),
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
