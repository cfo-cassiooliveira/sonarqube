#!/usr/bin/env bash
# Provisionamento idempotente do SonarQube pela Web API: senha do admin, segurança, Quality Gate padrão,
# projetos registrados e um token de análise por projeto.
# Pode rodar a cada "docker compose up": o que já existe é mantido; as condições do Quality Gate são sincronizadas.
set -euo pipefail

: "${SONAR_URL:?SONAR_URL is required}"
: "${SONAR_ADMIN_PASSWORD:?SONAR_ADMIN_PASSWORD is required}"
PROJECTS_FILE="${PROJECTS_FILE:-/provisioning/projects.json}"
TOKENS_DIR="${TOKENS_DIR:-/tokens}"
QUALITY_GATE="Workspace Way"
DEFAULT_ADMIN_PASSWORD="admin"

# Condições do Quality Gate (Constituição Art. V.3): métrica, operador e limite, sempre sobre código novo.
QUALITY_GATE_CONDITIONS='[
  {"metric": "new_violations",                 "op": "GT", "error": "0"},
  {"metric": "new_coverage",                   "op": "LT", "error": "80"},
  {"metric": "new_duplicated_lines_density",   "op": "GT", "error": "3"},
  {"metric": "new_security_hotspots_reviewed", "op": "LT", "error": "100"}
]'

# ---------------------------------------------------------------- utilitários HTTP
# Uso: api METHOD /api/path [campo=valor ...]  (POST envia form-urlencoded, GET envia query string)
api() {
  local method="$1" path="$2"
  shift 2
  local args=(-sS --fail-with-body -u "admin:${SONAR_ADMIN_PASSWORD}" -X "$method")
  if [[ "$method" == "GET" ]]; then
    args+=(-G)
  fi
  for field in "$@"; do
    args+=(--data-urlencode "$field")
  done
  curl "${args[@]}" "${SONAR_URL}${path}"
}

# Mensagens vão para o stderr: o stdout das funções é usado para devolver valores.
log() { echo "[provision] $*" >&2; }

wait_for_sonarqube() {
  for _ in $(seq 1 60); do
    if curl -fsS "${SONAR_URL}/api/system/status" 2>/dev/null | jq -e '.status == "UP"' >/dev/null; then
      return 0
    fi
    sleep 5
  done
  echo "SonarQube API did not become available" >&2
  exit 1
}

credentials_valid() {
  local password="$1"
  curl -fsS -u "admin:${password}" "${SONAR_URL}/api/authentication/validate" | jq -e '.valid == true' >/dev/null
}

# ---------------------------------------------------------------- senha do admin
ensure_admin_password() {
  if credentials_valid "$SONAR_ADMIN_PASSWORD"; then
    return 0
  fi
  if ! credentials_valid "$DEFAULT_ADMIN_PASSWORD"; then
    echo "Admin password is neither SONAR_ADMIN_PASSWORD nor the default one" >&2
    exit 1
  fi
  curl -sS --fail-with-body -u "admin:${DEFAULT_ADMIN_PASSWORD}" -X POST "${SONAR_URL}/api/users/change_password" \
    --data-urlencode "login=admin" --data-urlencode "previousPassword=${DEFAULT_ADMIN_PASSWORD}" \
    --data-urlencode "password=${SONAR_ADMIN_PASSWORD}" >/dev/null
  log "admin default password replaced"
}

# ---------------------------------------------------------------- segurança
ensure_security_settings() {
  # Nega acesso anônimo à UI e à API (Art. IV.3) e cria projetos novos como privados.
  api POST /api/settings/set "key=sonar.forceAuthentication" "value=true" >/dev/null
  api POST /api/projects/update_default_visibility "projectVisibility=private" >/dev/null
  log "security settings applied"
}

# ---------------------------------------------------------------- Quality Gate
ensure_quality_gate() {
  if ! api GET /api/qualitygates/list | jq -e --arg n "$QUALITY_GATE" '.qualitygates[] | select(.name == $n)' >/dev/null; then
    api POST /api/qualitygates/create "name=${QUALITY_GATE}" >/dev/null
    log "quality gate created: ${QUALITY_GATE}"
  fi
  sync_quality_gate_conditions
  api POST /api/qualitygates/set_as_default "name=${QUALITY_GATE}" >/dev/null
}

# O script é a fonte da verdade: cria, corrige ou remove condições até ficarem iguais às declaradas.
sync_quality_gate_conditions() {
  local current
  current="$(api GET /api/qualitygates/show "name=${QUALITY_GATE}" | jq -c '.conditions // []')"

  while read -r wanted; do
    local metric op error existing
    metric="$(jq -r '.metric' <<<"$wanted")"
    op="$(jq -r '.op' <<<"$wanted")"
    error="$(jq -r '.error' <<<"$wanted")"
    existing="$(jq -c --arg m "$metric" '.[] | select(.metric == $m)' <<<"$current")"
    if [[ -z "$existing" ]]; then
      api POST /api/qualitygates/create_condition "gateName=${QUALITY_GATE}" "metric=${metric}" "op=${op}" "error=${error}" >/dev/null
      log "quality gate condition created: ${metric} ${op} ${error}"
    elif ! jq -e --arg op "$op" --arg e "$error" '.op == $op and .error == $e' <<<"$existing" >/dev/null; then
      api POST /api/qualitygates/update_condition "id=$(jq -r '.id' <<<"$existing")" "metric=${metric}" "op=${op}" "error=${error}" >/dev/null
      log "quality gate condition updated: ${metric} ${op} ${error}"
    fi
  done < <(jq -c '.[]' <<<"$QUALITY_GATE_CONDITIONS")

  while read -r extra_id; do
    [[ -n "$extra_id" ]] || continue
    api POST /api/qualitygates/delete_condition "id=${extra_id}" >/dev/null
    log "quality gate condition removed: ${extra_id}"
  done < <(jq -r --argjson wanted "$QUALITY_GATE_CONDITIONS" \
    '($wanted | map(.metric)) as $m | .[] | select(.metric as $x | $m | index($x) | not) | .id' <<<"$current")
}

# ---------------------------------------------------------------- projetos e tokens
ensure_project() {
  local key="$1" name="$2"
  if api GET /api/projects/search "projects=${key}" | jq -e '.components | length > 0' >/dev/null; then
    return 0
  fi
  api POST /api/projects/create "project=${key}" "name=${name}" "visibility=private" "mainBranch=main" >/dev/null
  log "project created: ${key}"
}

# Um token de análise por projeto (privilégio mínimo). O valor só existe no arquivo; nunca vai para o log.
ensure_project_token() {
  local key="$1"
  local token_name="analysis-${key}" token_file="${TOKENS_DIR}/${key}.token"
  local token_exists
  token_exists="$(api GET /api/user_tokens/search | jq --arg n "$token_name" '[.userTokens[] | select(.name == $n)] | length > 0')"

  if [[ -s "$token_file" && "$token_exists" == "true" ]]; then
    return 0
  fi
  # O valor de um token só é devolvido na criação: sem o arquivo, revoga e gera de novo.
  if [[ "$token_exists" == "true" ]]; then
    api POST /api/user_tokens/revoke "name=${token_name}" >/dev/null
  fi
  local token
  token="$(api POST /api/user_tokens/generate "name=${token_name}" "type=PROJECT_ANALYSIS_TOKEN" "projectKey=${key}" | jq -r '.token')"
  (umask 077 && printf '%s' "$token" > "$token_file")
  log "analysis token written for project: ${key}"
}

ensure_projects() {
  while read -r project; do
    local key name
    key="$(jq -r '.key' <<<"$project")"
    name="$(jq -r '.name' <<<"$project")"
    ensure_project "$key" "$name"
    ensure_project_token "$key"
  done < <(jq -c '.[]' "$PROJECTS_FILE")
}

# ---------------------------------------------------------------- execução
wait_for_sonarqube
ensure_admin_password
ensure_security_settings
ensure_quality_gate
ensure_projects
log "done"
