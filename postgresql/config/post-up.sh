#!/usr/bin/env bash
# =============================================================================
# Hook : post-up.sh
# Exécuté APRÈS "docker compose up" par la commande "da up postgresql".
#
# Rôle : afficher les informations de connexion une fois le cluster démarré.
# =============================================================================

set -e

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  📦 Cluster PostgreSQL démarré"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  🐘 PostgreSQL"
echo "     Hôte     : localhost:5432"
echo "     Base     : app_db"
echo "     User     : app_user"
echo "     Password : changeme"
echo ""
echo "  🌐 Adminer (interface web)"
echo "     URL      : http://localhost:8080"
echo "     Serveur  : postgres  (pré-rempli)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
