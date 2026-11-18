# Índice — SonarQube (leia isto antes dos docs longos)

**ADRs**
- 0001 SonarQube Community Build 26.11 + PostgreSQL 17 em Docker — Aceito — `docs/adr/0001-stack-sonarqube-community.md`

**Specs**: nenhuma (projeto de infraestrutura, sem `docs/specs/`).

**Comandos**: `./scripts/generate-env.sh && docker compose up -d --build` · `./scripts/smoke-test.sh` · `./scripts/smoke-api.sh` · `./scripts/scan.sh <pasta-do-projeto>`

**Onde procurar**: regras e Quality Gate "Workspace Way" → `CLAUDE.md`; provisionamento → `provisioning/`; decisão da stack → ADR-0001; integração com Grafana → seção "Grafana" do `CLAUDE.md`.
