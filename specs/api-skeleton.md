# API skeleton (FastAPI)

## Problema
Repo novo (`app-manb-ms`), sem estrutura nenhuma. Precisa de uma base de backend FastAPI para
servir de campo de testes para integração com o `noskoski-portal` (Backstage), incluindo deploy
num cluster Rancher local.

## Proposta
- FastAPI + Uvicorn, configuração via `pydantic-settings`.
- Layout `app/` (não `src/`) com `core/` (config) e `api/routes/` (routers por domínio),
  para crescer por domínio conforme o serviço ganhar novas funcionalidades.
- `pyproject.toml` (hatchling) como fonte única de dependências — sem `requirements.txt`.
- Docker multi-stage simples (`python:3.12-slim`), imagem publicada como
  `mnoskoski/app-manb-ms` no Docker Hub.
- GitHub Actions (`.github/workflows/ci.yml`): job de lint+test (`ruff` + `pytest`) que precisa
  passar antes do job de build/push da imagem. Push só acontece fora de PR (branch `main` ou tag
  `vX.Y.Z`).
- `catalog-info.yaml` na raiz para registro no Backstage (`noskoski-portal`), seguindo o mesmo
  padrão do outro experimento local (`lab-backstage/app-fast-api`).
- `k8s/` com Deployment + Service básicos para rodar no Rancher Desktop local, consumindo a
  imagem publicada no Docker Hub.

## Escopo
Esqueleto rodável: endpoint `/health`, endpoint raiz, testes, Dockerfile, CI/CD para Docker Hub,
catalog-info.yaml, manifests k8s mínimos.

## Fora de escopo
- Banco de dados / persistência.
- Autenticação/autorização.
- Registro efetivo do componente no catalog do `noskoski-portal` (feito manualmente pelo
  usuário, adicionando a location no `app-config.yaml` do portal ou importando a URL do
  catalog-info.yaml).
- Deploy automatizado no Rancher (CD) — por ora só os manifests, aplicados manualmente.

## Notas de implementação
- Owner do `catalog-info.yaml` aponta para `group:default/guests`, que é o único grupo
  atualmente existente no catalog do `noskoski-portal` (`examples/org.yaml`) — evita entidade
  órfã. Ajustar quando houver um Group/User real cadastrado.
- Secrets necessários no GitHub (Settings → Secrets → Actions) para o job de build/push:
  `DOCKERHUB_USERNAME` e `DOCKERHUB_TOKEN` (token de acesso do Docker Hub, não a senha).
