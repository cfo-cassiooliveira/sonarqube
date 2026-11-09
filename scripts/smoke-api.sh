#!/usr/bin/env bash
# Parte do smoke test que conversa com a Web API (roda dentro da imagem do provisioner, que tem curl e jq).
# Chamado pelo scripts/smoke-test.sh; não use direto. Subcomandos: checks | prepare | verify | cleanup
set -euo pipefail

: "${SONAR_URL:?}" "${SONAR_ADMIN_PASSWORD:?}" "${SONAR_SYSTEM_PASSCODE:?}"
FIXTURE_KEY="smoke-test-fixture"
QUALITY_GATE="Workspace Way"
failures=0

# Uso: request GET|POST /api/path [campo=valor ...]
request() {
  local method="$1" path="$2"
  shift 2
  local args=(-sS --fail-with-body -u "admin:${SONAR_ADMIN_PASSWORD}" -X "$method")
  [[ "$method" == "GET" ]] && args+=(-G)
  for field in "$@"; do
    args+=(--data-urlencode "$field")
  done
  curl "${args[@]}" "${SONAR_URL}${path}"
}

api() { request GET "$@"; }
api_post() { request POST "$@"; }

check() {
  local description="$1" ok="$2"
  if [[ "$ok" == "true" ]]; then echo "✅ ${description}"; else echo "❌ ${description}"; failures=$((failures + 1)); fi
}

checks() {
  local health anonymous_status gate
  health="$(curl -fsS -H "X-Sonar-Passcode: ${SONAR_SYSTEM_PASSCODE}" "${SONAR_URL}/api/system/health" | jq -r '.health')"
  check "saúde do SonarQube é GREEN" "$([[ "$health" == "GREEN" ]] && echo true || echo false)"

  anonymous_status="$(curl -s -o /dev/null -w '%{http_code}' "${SONAR_URL}/api/projects/search")"
  check "acesso anônimo à API é recusado (401)" "$([[ "$anonymous_status" == "401" ]] && echo true || echo false)"

  check "senha padrão do admin foi trocada" \
    "$(curl -s -u admin:admin "${SONAR_URL}/api/authentication/validate" | jq '.valid == false')"

  gate="$(api /api/qualitygates/show "name=${QUALITY_GATE}")"
  check "Quality Gate '${QUALITY_GATE}' é o padrão" "$(jq '.isDefault == true' <<<"$gate")"
  check "Quality Gate tem as 4 condições da Constituição" "$(jq '
    [.conditions[] | "\(.metric) \(.op) \(.error)"] | sort ==
    ["new_coverage LT 80", "new_duplicated_lines_density GT 3", "new_security_hotspots_reviewed LT 100", "new_violations GT 0"]' <<<"$gate")"

  while read -r key; do
    check "projeto ${key} existe e é privado" \
      "$(api /api/projects/search "projects=${key}" | jq '.components | length == 1 and .[0].visibility == "private"')"
    check "token de análise de ${key} existe" "$([[ -s "/tokens/${key}.token" ]] && echo true || echo false)"
  done < <(jq -r '.[].key' /provisioning/projects.json)
}

delete_fixture() {
  if api /api/projects/search "projects=${FIXTURE_KEY}" | jq -e '.components | length > 0' >/dev/null; then
    api_post /api/projects/delete "project=${FIXTURE_KEY}" >/dev/null
  fi
  if api /api/user_tokens/search | jq -e --arg n "smoke-${FIXTURE_KEY}" '.userTokens[] | select(.name == $n)' >/dev/null; then
    api_post /api/user_tokens/revoke "name=smoke-${FIXTURE_KEY}" >/dev/null
  fi
  rm -f "/tokens/${FIXTURE_KEY}.token"
}

prepare() {
  delete_fixture
  api_post /api/projects/create "project=${FIXTURE_KEY}" "name=Smoke Test Fixture" "visibility=private" >/dev/null
  local token
  token="$(api_post /api/user_tokens/generate "name=smoke-${FIXTURE_KEY}" "type=PROJECT_ANALYSIS_TOKEN" "projectKey=${FIXTURE_KEY}" | jq -r '.token')"
  (umask 077 && printf '%s' "$token" > "/tokens/${FIXTURE_KEY}.token")
}

verify() {
  local status issues
  status="$(api /api/qualitygates/project_status "projectKey=${FIXTURE_KEY}")"
  check "Quality Gate da 2ª análise reprovou (ERROR)" "$(jq '.projectStatus.status == "ERROR"' <<<"$status")"
  check "condição new_violations foi a causa" \
    "$(jq '[.projectStatus.conditions[] | select(.metricKey == "new_violations" and .status == "ERROR")] | length == 1' <<<"$status")"
  issues="$(api /api/issues/search "components=${FIXTURE_KEY}" "issueStatuses=OPEN")"
  check "issues detectadas só no arquivo novo (compare.js)" \
    "$(jq '.total > 0 and ([.issues[].component | endswith("src/compare.js")] | all)' <<<"$issues")"
}

case "${1:-}" in
  checks) checks ;;
  prepare) prepare ;;
  verify) verify ;;
  cleanup) delete_fixture ;;
  *) echo "Usage: smoke-api.sh checks|prepare|verify|cleanup" >&2; exit 2 ;;
esac
exit "$failures"
