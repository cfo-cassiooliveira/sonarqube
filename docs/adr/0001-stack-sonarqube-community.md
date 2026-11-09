# ADR-0001: SonarQube Community Build 26.11 + PostgreSQL 17 em Docker

- **Status**: Aceito
- **Data**: 2026-11-09
- **Decisores**: Cassio Oliveira (responsável técnico)
- **Artigos da Constituição relacionados**: Art. V.2 e V.3 (Quality Gate), Art. IV.2 (autenticação), Art. IV.4 (segredos)

## Contexto

A Constituição exige o **Quality Gate do SonarQube** aprovado antes de qualquer merge, mas não havia servidor: o CI do
legado pulava o job `quality-gate`. Precisamos de um SonarQube local em Docker, reutilizável pelos projetos do
`C:\Workspace` e configurado sem passos manuais na UI, no mesmo molde do projeto `graylog`.

## Decisão

1. Projeto próprio em `C:\Workspace\sonarqube`, separado dos sistemas analisados.
2. **SonarQube Community Build 26.11 + PostgreSQL 17.11** (a matriz suporta PostgreSQL 15 a 18), imagens por
   **tag + digest**.
3. Porta **`127.0.0.1:9001`** (a 9000 é do Graylog). PostgreSQL só na rede interna.
4. **Rede Docker `quality`** (nome fixo): o `sonar-scanner-cli` em Docker entra nela e usa `http://sonarqube:9000`.
5. **Configuração como código**: um container `provisioner` (alpine + curl + jq) troca a senha padrão, força
   autenticação, cria o Quality Gate `Workspace Way` como padrão (condições sincronizadas a cada execução), cria os
   projetos de `projects.json` e gera um **Project Analysis Token por projeto** em `.tokens/` (fora do git).
6. Análise por **script local** (`scripts/scan.sh` e o `scripts/sonar-analysis.sh` do legado). O CI do legado mantém o
   job opcional até haver um servidor acessível pelos runners do GitHub.
7. O Site-Principal ganhou testes (Vitest + jsdom) com cobertura lcov, em vez de um gate sem cobertura para sites.

## Alternativas consideradas

| Alternativa | Prós | Contras | Motivo da rejeição |
|---|---|---|---|
| Developer Edition | Análise de branches e PRs, comentário no PR | Licença paga por linhas de código | Custo sem necessidade imediata |
| SonarQube Cloud | Sem infraestrutura, PR decoration | Código enviado a terceiros; plano pago para privados | Preferência por infraestrutura local |
| Banco H2 embutido | Zero configuração | Não suportado para uso real, sem upgrade | Não é suportado pela SonarSource |
| Token global de análise | Um só segredo | Um vazamento afeta todos os projetos | Privilégio mínimo |
| Gate sem cobertura para sites estáticos | Sites sem testes passariam | Afrouxa a Constituição | Optamos por adicionar testes |

## Consequências

- **Positivas**: `docker compose up -d` entrega o SonarQube pronto e reproduzível. O Quality Gate da Constituição passa
  a ser medido de verdade e o smoke test prova que ele reprova código ruim.
- **Negativas / riscos**:
  - O Community Build **não analisa branches nem PRs**: a regra "análise de PR habilitada" do `testing-quality.md`
    fica pendente. Cada análise local atualiza a branch principal do projeto.
  - **Login local (admin)**, exceção ao Art. IV.2 enquanto não existir Keycloak no workspace. Ação futura: autenticação
    SAML/OIDC com o Keycloak.
  - Sem TLS: uso só local/dev. Em servidor compartilhado, use proxy reverso com TLS e um cofre de segredos.
  - O host precisa de `vm.max_map_count ≥ 524288` (WSL2 do Docker Desktop).
- **Ações decorrentes**: novos projetos entram no `projects.json`. Quando houver servidor acessível pelo CI (edição paga
  ou SonarQube Cloud), habilitar a análise de PR e os segredos `SONAR_TOKEN`/`SONAR_HOST_URL` nos repositórios.
