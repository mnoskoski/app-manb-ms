# app-manb-ms

Microsserviço FastAPI usado como campo de testes: integração com Backstage
(`noskoski-portal`), CI/CD para Docker Hub, e deploy num cluster Rancher local. Não é um
produto — é um laboratório para validar esses padrões.

## Arquitetura

- `app/main.py` — cria a `FastAPI` app e inclui os routers.
- `app/core/config.py` — `Settings` via `pydantic-settings` (env vars com prefixo `APP_`).
- `app/api/routes/` — um módulo de router por domínio (hoje só `health.py`). Ao crescer, novos
  domínios entram como novo módulo aqui + `app.include_router(...)` em `main.py`.
- `tests/` — pytest + `TestClient` do FastAPI.
- `Dockerfile` — build single-stage `python:3.12-slim`, `pip install .` a partir do
  `pyproject.toml` (sem `requirements.txt`).
- `.github/workflows/ci.yml` — lint (`ruff`) + testes (`pytest`); só depois builda e publica a
  imagem em `mnoskoski/app-manb-ms` no Docker Hub (branch `main` e tags `vX.Y.Z`; PRs só
  buildam, não publicam).
- `catalog-info.yaml` — registro Backstage (`Component`, `type: service`), para importar no
  `noskoski-portal`.
- `k8s/` — Deployment + Service mínimos para rodar a imagem publicada num cluster Rancher local.

## Development workflow

- Antes de adicionar algo não-trivial, escreva um spec curto em `specs/` (ver
  `specs/README.md`). Não pule essa etapa achando que é óbvio — o spec é o que permite retomar
  o trabalho depois sem re-derivar as decisões.
- Siga o padrão já existente na camada que está sendo tocada (ex.: novo endpoint = novo módulo
  em `app/api/routes/`, não tudo dentro de `main.py`).
- Rodar localmente:
  ```
  pip install -e ".[dev]"
  uvicorn app.main:app --reload
  ```
- Rodar testes/lint:
  ```
  pytest
  ruff check .
  ```
- Build/push manual da imagem (o CI já faz isso, mas para testar local):
  ```
  docker build -t mnoskoski/app-manb-ms:dev .
  ```
- Secrets do GitHub Actions necessários no repo (`DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`) devem
  ser configurados manualmente em Settings → Secrets and variables → Actions.
