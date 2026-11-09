# SonarQube — qualidade de código do C:\Workspace

SonarQube **Community Build 26.11** + PostgreSQL 17 em Docker, **provisionado automaticamente**: troca da senha
padrão, acesso anônimo bloqueado, Quality Gate do workspace como padrão, projetos e tokens de análise. Os projetos
[legado](../legado), [Site-Principal](../Site-Principal) e [Site-Menu](../Site-Menu) são analisados aqui.
Decisões: [ADR-0001](docs/adr/0001-stack-sonarqube-community.md).

## Pré-requisito do host: `vm.max_map_count`

O Elasticsearch embutido no SonarQube exige `vm.max_map_count ≥ 524288` (o padrão do Docker Desktop é 262144).

- **Permanente (recomendado)**: em `%USERPROFILE%\.wslconfig`, na seção `[wsl2]`, adicione
  `kernelCommandLine = "sysctl.vm.max_map_count=524288"` e rode `wsl --shutdown` (reinicia o Docker Desktop).
- **Só até o próximo reinício do WSL**: `wsl -d docker-desktop sysctl -w vm.max_map_count=524288`.

Docker Desktop com pelo menos 6 GB de memória se o Graylog também estiver de pé.

## Como subir

```bash
./scripts/generate-env.sh      # cria o .env com segredos aleatórios (nunca versionado)
docker compose up -d --build   # sobe postgres e sonarqube e roda o provisionamento
```

Acesse **http://localhost:9001** (a porta 9000 é do Graylog) com o usuário `admin` e a senha `SONAR_ADMIN_PASSWORD`
do `.env`. A primeira subida leva de 1 a 2 minutos.

Com o Graylog de pé, os logs do SonarQube e do PostgreSQL vão para o stream `SonarQube - Infra`:

```bash
docker compose -f docker-compose.yml -f docker-compose.graylog.yml up -d
```

## O que é provisionado (`provisioning/provision.sh`, idempotente)

| Item | Detalhe |
|---|---|
| Admin | A senha padrão `admin/admin` é trocada pela `SONAR_ADMIN_PASSWORD` |
| Segurança | `sonar.forceAuthentication=true` (anônimo recebe 401) e projetos novos privados |
| Quality Gate `Workspace Way` (padrão) | Código novo: **0 issues**, **cobertura ≥ 80%**, **duplicação ≤ 3%**, **100% dos hotspots revisados** (Constituição, Art. V.3) |
| Projetos ([`projects.json`](provisioning/projects.json)) | `legado-cadastro-usuarios`, `site-principal`, `site-menu` |
| Tokens | Um token de análise **por projeto** (só analisa aquele projeto), salvo em `.tokens/<key>.token` |

As condições do gate são sincronizadas a cada execução: alterações feitas pela UI são desfeitas (o script é a fonte da
verdade). Para mudar, edite o script e rode `docker compose run --rm provisioner`.

O SonarQube ignora cobertura e duplicação quando a mudança tem menos de 20 linhas novas ("Clean as You Code"); as issues
novas sempre contam.

## Como analisar um projeto

| Projeto | Comando (na pasta do projeto) |
|---|---|
| legado (.NET + Angular) | `./scripts/sonar-analysis.sh` |
| Site-Principal | `npm run test:coverage && ../sonarqube/scripts/scan.sh .` |
| Site-Menu | `../sonarqube/scripts/scan.sh .` |

O [`scripts/scan.sh`](scripts/scan.sh) roda o `sonar-scanner-cli` em Docker na rede `quality`, lê a key do
`sonar-project.properties` do projeto, usa o token de `.tokens/` (ou `SONAR_TOKEN`) e **termina com erro se o Quality
Gate reprovar**.

### Projeto novo

1. Adicione `{ "key": "...", "name": "..." }` ao [`provisioning/projects.json`](provisioning/projects.json).
2. `docker compose up -d --build provisioner` (cria o projeto e o token).
3. No projeto: `sonar-project.properties` (ou o scanner do .NET) e os testes com cobertura (lcov/OpenCover/VS XML).

## Variáveis de ambiente (`.env`)

| Variável | Obrigatória | Para que serve |
|---|---|---|
| `POSTGRES_PASSWORD` | Sim | Senha do PostgreSQL (rede interna) |
| `SONAR_ADMIN_PASSWORD` | Sim | Senha do `admin` (UI/API e provisionamento). A política exige 12+ caracteres com maiúscula, minúscula, dígito e especial |
| `SONAR_SYSTEM_PASSCODE` | Sim | Passcode do monitoramento, usado pelo healthcheck (`/api/system/health`) |

O `scripts/generate-env.sh` preenche tudo. O `.env` e a pasta `.tokens/` estão no `.gitignore`, e o
[`.env.example`](.env.example) só documenta as variáveis, sem nenhum valor.

## Teste (smoke test ponta a ponta)

```bash
./scripts/smoke-test.sh
```

Confere o provisionamento (saúde, 401 anônimo, senha padrão trocada, gate padrão com as 4 condições, projetos privados e
tokens) e faz duas análises reais de um projeto sintético (`tests/fixtures`): a 1ª, limpa, **aprova**; a 2ª, com issues
em código novo, **reprova** pela condição `new_violations`. O projeto sintético é removido no final.

## Segurança

- Porta publicada só em `127.0.0.1:9001`. O PostgreSQL fica só na rede interna.
- Segredos só no `.env`; tokens só em `.tokens/`, nunca em log. O `scan.sh` passa o token ao container por variável
  herdada, fora da linha de comando.
- Tokens por projeto do tipo *Project Analysis Token*: um token vazado só permite analisar aquele projeto. Para
  rotacionar, apague o arquivo em `.tokens/` e rode o provisionamento (o token antigo é revogado).
- Login local (admin) e uso **local/desenvolvimento** sem TLS: veja as ressalvas do ADR-0001.
