#!/usr/bin/env bash
# Gera o .env local com segredos aleatórios (nunca versionado). Não sobrescreve um .env existente.
# Uso: ./scripts/generate-env.sh            (mostra onde está a senha do admin, sem imprimi-la)
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ -f .env ]]; then
  echo ".env já existe; nada foi alterado. Apague-o para gerar novos segredos."
  exit 0
fi

random() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$1"; }

umask 077
cat > .env <<EOF
# Gerado por scripts/generate-env.sh em $(date -u +%Y-%m-%dT%H:%M:%SZ). NUNCA versione este arquivo.
POSTGRES_PASSWORD=$(random 32)
# O sufixo garante a política de senha do SonarQube (maiúscula, minúscula, dígito e caractere especial).
SONAR_ADMIN_PASSWORD=$(random 24)#Aa1
SONAR_SYSTEM_PASSCODE=$(random 40)
EOF

echo ".env criado. Usuário da UI: admin — senha em SONAR_ADMIN_PASSWORD no .env."
