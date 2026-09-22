# AWS Secrets Manager integration (dev/crm/API_key)

## Problema
Precisamos que o app consiga usar uma API key de um CRM, guardada no AWS Secrets Manager
(`dev/crm/API_key`, JSON com uma chave `API_KEY`), sem nunca commitar o valor em texto puro.

## Proposta
Duas estratégias, propositalmente redundantes, cada uma valendo para um contexto diferente:

1. **SDK (boto3) direto no app** — `app/core/secrets.py`. Usada para dev local (rodando
   `uvicorn` fora do container): boto3 usa a cadeia de credenciais padrão da AWS CLI
   (`~/.aws/credentials`, já configurada via `aws configure`), sem nenhuma env var extra.
2. **External Secrets Operator (ESO)** rodando no cluster — sincroniza o secret do AWS Secrets
   Manager para um `Secret` nativo do k8s, que o Deployment injeta como env var
   (`APP_CRM_API_KEY`). Rodando em cluster, o pod do app **não tem nenhuma credencial AWS
   própria** — só quem fala com a AWS é o ESO.

`app/core/secrets.py:get_crm_api_key()` decide sozinho qual caminho usar: se
`APP_CRM_API_KEY` estiver setada (caminho ESO/k8s), usa direto; senão, busca via boto3
(caminho SDK/local).

### Padrão de credencial do ESO (pensado pra múltiplos apps no mesmo cluster)
- Um usuário IAM dedicado só pro ESO (`eso-dev-secrets-reader`), não reaproveita o
  `mnoskoski-cli` (que tem `AdministratorAccess`).
- Policy mínima: `secretsmanager:GetSecretValue` + `DescribeSecret`, escopada ao prefixo
  `dev/*` (`arn:aws:secretsmanager:*:004976996192:secret:dev/*`) — cobre qualquer secret
  futuro nesse padrão de nome, sem precisar editar a policy de novo.
- **Um `ClusterSecretStore` só, por cluster** (`external-secrets/cluster-secret-store.yaml`),
  não um `SecretStore` por app/namespace. Cada app declara seu próprio `ExternalSecret`
  referenciando esse mesmo store — é assim que outros apps no mesmo cluster vão reusar essa
  autenticação depois, sem duplicar credencial.
- A instalação do ESO em si (Helm, namespace, IAM, ClusterSecretStore) mora em
  `external-secrets/` na raiz do repo, separada de `k8s/` — é infra de cluster, não deste app
  especificamente, e o objetivo é poder replicar em outro ambiente/cluster (ver
  `external-secrets/README.md`).
- A credencial do ESO (access key/secret do `eso-dev-secrets-reader`) foi criada e inserida no
  k8s Secret (`aws-secretsmanager-creds`, namespace `external-secrets`) manualmente pelo
  usuário, nunca por mim — mesma regra de nunca eu manusear credenciais AWS.

## Escopo
- `app/core/secrets.py` + `app/core/config.py` (campos `aws_region`, `crm_api_key_secret_name`,
  `crm_api_key`).
- `app/api/routes/crm.py`: `GET /integrations/crm/status` — só confirma que o secret carregou
  (`{"crm_api_key_loaded": true}` ou 503), nunca retorna o valor.
- `external-secrets/` (raiz do repo): instalação do ESO — `namespace.yaml`, `values.yaml`
  (Helm, chart `external-secrets/external-secrets` v2.11.0), `bootstrap-iam.sh` +
  `iam-policy.json.tmpl` (cria usuário/policy IAM, idempotente, sem tocar em credencial),
  `cluster-secret-store.yaml`, `README.md` com o passo a passo pra replicar em outro ambiente.
- `k8s/external-secrets/external-secret.yaml`: `ExternalSecret` específico deste app.
- `k8s/deployment.yaml`: env `APP_CRM_API_KEY` via `secretKeyRef` (optional, pra não travar o
  pod se o `ExternalSecret` ainda não sincronizou).

## Fora de escopo
- Uso real da CRM API key para chamar alguma API de CRM de verdade (só a wiring/plumbing).
- Rotação automática do secret ou do access key do ESO.
- IRSA — não se aplica a um cluster local Rancher; por isso o ESO usa credencial estática.

## Notas de implementação
- `get_secret()`/`get_crm_api_key()` são `lru_cache`d — uma chamada AWS por processo, não por
  request.
- `ClusterSecretStore` é cluster-scoped (não fica em nenhum namespace específico); o
  `ExternalSecret` de cada app fica no namespace do próprio app e referencia o store pelo nome.
