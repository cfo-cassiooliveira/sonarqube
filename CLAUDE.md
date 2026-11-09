# SonarQube — qualidade de código

> Herda a Constituição (`C:\Workspace\CLAUDE.md`) e o steering (`C:\Workspace\.claude\rules\`), em especial
> `testing-quality.md`. Projeto de infraestrutura (sem código de aplicação): aplicam-se Art. IV, V.2/V.3, X e XI.

## Propósito

SonarQube Community Build local em Docker que mede o Quality Gate dos projetos do workspace, com configuração como código.

## Estrutura

```
docker-compose.yml          postgres, sonarqube, provisioner; rede externa "quality"
docker-compose.graylog.yml  logs para o Graylog (GELF UDP, tags sonarqube / sonarqube-db)
provisioning/provision.sh   provisionamento idempotente via Web API (senha, segurança, Quality Gate, projetos, tokens)
provisioning/projects.json  projetos registrados (fonte da verdade)
scripts/generate-env.sh     gera o .env com segredos aleatórios
scripts/scan.sh             análise de projetos não .NET (sonar-scanner-cli em Docker) com espera do Quality Gate
scripts/smoke-test.sh       teste ponta a ponta (orquestra; a parte da API fica em scripts/smoke-api.sh)
tests/fixtures/             projeto sintético v1 (limpo) e v2 (com issues) do smoke test
docs/adr/                   decisões
```

## Regras deste projeto

- Imagens fixadas por **tag + digest**; confira a matriz de requisitos (PostgreSQL 15–18) ao atualizar.
- Toda configuração entra pelo `provision.sh` (nunca só pela UI). As condições do Quality Gate `Workspace Way` são
  sincronizadas a cada execução e só podem **endurecer** a Constituição, nunca afrouxar.
- Novo projeto analisado → entrada no `projects.json` (key em inglês, kebab-case) e token próprio.
- Tokens são *Project Analysis Tokens* em `.tokens/` (fora do git). Nunca imprima token em log ou o passe na linha de
  comando do `docker run` (use `-e SONAR_TOKEN` herdado).
- No Git Bash (Windows), comandos com caminhos ou argumentos `/x:` usam `MSYS_NO_PATHCONV=1` e `pwd -W`.
- **Idioma (Art. I)**: keys de projeto, métricas e mensagens de log do provisionamento em inglês; comentários,
  documentação e saída do smoke test em PT-BR. O nome `Workspace Way` segue a convenção do `Sonar way` embutido.
- Cada mudança roda o `./scripts/smoke-test.sh`.

## Comandos

```bash
./scripts/generate-env.sh && docker compose up -d --build
docker compose run --rm provisioner                       # reaplica o provisionamento
./scripts/smoke-test.sh
./scripts/scan.sh <pasta-do-projeto>
```
