#!/usr/bin/env bash
# Smoke test ponta a ponta do SonarQube: confere o provisionamento (saúde, acesso anônimo, Quality Gate, projetos,
# tokens) e faz duas análises reais de um projeto sintético: a 1ª (limpa) aprova e a 2ª (com issues novas) reprova.
# Uso (na raiz do projeto, com o stack de pé): ./scripts/smoke-test.sh
set -euo pipefail

cd "$(dirname "$0")/.."
root="$(pwd -W 2>/dev/null || pwd)"
failures=0

# Executa o smoke-api.sh dentro da imagem do provisioner (curl + jq), com o passcode do healthcheck.
# --no-deps: sem ele o compose recriaria o SonarQube só com o docker-compose.yml (perdendo o override do Graylog).
smoke_api() {
  MSYS_NO_PATHCONV=1 docker compose run --rm --no-deps -T -e SONAR_SYSTEM_PASSCODE \
    -v "${root}/scripts:/scripts:ro" --entrypoint /scripts/smoke-api.sh provisioner "$1" 2>/dev/null
}

check() {
  local description="$1" ok="$2"
  if [[ "$ok" == "true" ]]; then echo "✅ ${description}"; else echo "❌ ${description}"; failures=$((failures + 1)); fi
}

set -a
# shellcheck disable=SC1091
source .env
set +a

trap 'smoke_api cleanup >/dev/null || true' EXIT

# O smoke test roda sobre a stack como ela foi subida (inclusive com o docker-compose.graylog.yml): não pode recriá-la.
sonarqube_container="$(docker compose ps -q sonarqube)"

smoke_api checks || failures=$((failures + $?))
smoke_api prepare

if ./scripts/scan.sh tests/fixtures/v1 -Dsonar.projectVersion=1 >/dev/null 2>&1; then first=true; else first=false; fi
check "1ª análise (código limpo) aprovou no Quality Gate" "$first"

if ./scripts/scan.sh tests/fixtures/v2 -Dsonar.projectVersion=2 >/dev/null 2>&1; then second=false; else second=true; fi
check "2ª análise (issues em código novo) falhou o scanner" "$second"

smoke_api verify || failures=$((failures + $?))

# Regressão: "docker compose run" sem --no-deps recriava o SonarQube só com o docker-compose.yml, desligando o envio
# de logs ao Graylog sem aviso.
check "smoke test não recria o SonarQube (mantém o override com que a stack subiu)" \
  "$([[ -n "$sonarqube_container" && "$(docker compose ps -q sonarqube)" == "$sonarqube_container" ]] && echo true || echo false)"

if [[ "$failures" -gt 0 ]]; then
  echo "Smoke test failed: ${failures} check(s)"
  exit 1
fi
echo "Smoke test passed"
