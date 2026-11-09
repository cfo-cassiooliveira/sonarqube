#!/usr/bin/env bash
# Analisa um projeto não .NET (JS, HTML, CSS...) com o sonar-scanner-cli em Docker e espera o Quality Gate.
# Termina com erro se o Quality Gate reprovar. O projeto precisa de um sonar-project.properties na raiz.
# Uso: <caminho>/sonarqube/scripts/scan.sh <pasta-do-projeto> [-Dpropriedade=valor ...]
# Token: SONAR_TOKEN do ambiente ou o arquivo .tokens/<projectKey>.token gerado pelo provisionamento.
set -euo pipefail

SCANNER_IMAGE="sonarsource/sonar-scanner-cli:12.3.1.4302_8.3.1@sha256:38207bba3d98c8ce6f6c051ea2b9f05a24480da78c9ee5945ceafc3d9de02b88"
sonarqube_root="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -lt 1 || ! -f "$1/sonar-project.properties" ]]; then
  echo "Usage: scan.sh <project-dir> [-Dkey=value ...] (project-dir must contain sonar-project.properties)" >&2
  exit 2
fi
project_dir="$1"
shift

project_key="$(grep -E '^sonar\.projectKey=' "${project_dir}/sonar-project.properties" | cut -d= -f2- | tr -d '\r')"
token_file="${sonarqube_root}/.tokens/${project_key}.token"
if [[ -z "${SONAR_TOKEN:-}" ]]; then
  if [[ ! -s "$token_file" ]]; then
    echo "No SONAR_TOKEN and no token file for project '${project_key}'. Run the provisioner first." >&2
    exit 2
  fi
  SONAR_TOKEN="$(cat "$token_file")"
fi
export SONAR_TOKEN

# No Git Bash (Windows) o Docker precisa do caminho no formato C:/...; "pwd -W" só existe lá.
host_dir="$(cd "$project_dir" && (pwd -W 2>/dev/null || pwd))"

# O token vai por variável herdada (-e SONAR_TOKEN sem valor), não na linha de comando.
# O git do container rejeita o volume montado (dono diferente): safe.directory libera só /usr/src.
# A imagem usa /tmp/.scannerwork como diretório de trabalho: o projeto não fica com sujeira.
MSYS_NO_PATHCONV=1 docker run --rm --network quality \
  -e SONAR_HOST_URL=http://sonarqube:9000 -e SONAR_TOKEN \
  -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0=/usr/src \
  -v "${host_dir}:/usr/src" \
  -v sonar-scanner-cache:/opt/sonar-scanner/.sonar/cache \
  "$SCANNER_IMAGE" \
  -Dsonar.qualitygate.wait=true \
  "$@"
