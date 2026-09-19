# app-manb-ms

Microsserviço backend em FastAPI — campo de testes para integração com Backstage
(`noskoski-portal`) e experimentos que depois podem migrar para o `project-eternum`.

## Rodando localmente

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
uvicorn app.main:app --reload
```

API em `http://localhost:8000`, docs interativos em `http://localhost:8000/docs`.

## Testes e lint

```bash
pytest
ruff check .
```

## Docker

```bash
docker build -t mnoskoski/app-manb-ms:dev .
docker run -p 8000:8000 mnoskoski/app-manb-ms:dev
```

## CI/CD

`.github/workflows/ci.yml` roda lint + testes em todo push/PR, e builda + publica a imagem em
[hub.docker.com/r/mnoskoski/app-manb-ms](https://hub.docker.com/repositories/mnoskoski) quando
há push em `main` ou tag `vX.Y.Z`. Requer os secrets `DOCKERHUB_USERNAME` e `DOCKERHUB_TOKEN`
configurados no repositório GitHub.

## Kubernetes (Rancher local)

```bash
kubectl apply -f k8s/deployment.yaml -f k8s/service.yaml
```

## Backstage

`catalog-info.yaml` na raiz registra este serviço como `Component` no catalog. Para importar no
`noskoski-portal`, adicione a URL do arquivo como uma `Location` no `app-config.yaml` do portal,
ou use "Register existing component" na UI do Backstage.

## Estrutura e processo

Ver [`CLAUDE.md`](CLAUDE.md) para arquitetura e workflow de desenvolvimento, e [`specs/`](specs/)
para o histórico de decisões (spec-driven development).
