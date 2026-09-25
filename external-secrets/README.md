# External Secrets Operator — cluster install

Infra de cluster, não específica deste app: instala o [External Secrets
Operator](https://external-secrets.io/) (ESO) e um `ClusterSecretStore` único
apontando pro AWS Secrets Manager. Qualquer app no cluster reusa esse mesmo
store declarando seu próprio `ExternalSecret` (o do app-manb-ms está em
[`../k8s/external-secrets/external-secret.yaml`](../k8s/external-secrets/external-secret.yaml)).

Pensado pra ser replicado em outro cluster/ambiente (ex: um "prod" separado)
sem reescrever nada — só trocar os parâmetros de ambiente indicados abaixo.

## Pré-requisitos

- `kubectl` apontando pro cluster de destino (`kubectl config current-context`)
- `helm` (usamos aqui: `~/.rd/bin/helm`, v4.2.3)
- `aws` CLI autenticado com permissão de IAM (`iam:CreateUser`, `iam:PutUserPolicy`)
  na conta AWS de destino

## Passo a passo

### 1. Namespace

```bash
kubectl apply -f namespace.yaml
```

### 2. IAM — usuário + policy (sem tocar em credencial)

Uma identidade por **cluster** (fronteira de confiança), não por ambiente. Ver
[`../specs/secrets-naming-convention.md`](../specs/secrets-naming-convention.md)
pro raciocínio completo.

```bash
# cluster local de laboratório (só dev/*):
./bootstrap-iam.sh

# cluster on-prem compartilhado por dev/test/uat — uma identidade, 3 prefixos:
SECRET_PREFIXES='dev/* test/* uat/*' \
  IAM_USER_NAME='eso-nonprod-secrets-reader' \
  IAM_POLICY_NAME='ESONonProdSecretsManagerRead' \
  ./bootstrap-iam.sh

# cluster de prod — identidade própria, nunca reaproveitada:
SECRET_PREFIXES='prod/*' \
  IAM_USER_NAME='eso-prod-secrets-reader' \
  IAM_POLICY_NAME='ESOProdSecretsManagerRead' \
  ./bootstrap-iam.sh
```

Isso cria (ou atualiza, é idempotente) um usuário IAM dedicado com policy
mínima: `secretsmanager:GetSecretValue` + `DescribeSecret`, escopada aos
prefixos indicados (um ou vários — a policy vira um array de `Resource`).
Nunca dá `AdministratorAccess` nem reusa outro usuário — cada *cluster* tem
seu próprio usuário ESO, mesmo que esse cluster rode várias envs.

### 3. Access key + k8s Secret (manual, de propósito)

O script acima **não** cria a access key nem grava nada no cluster — isso é
sempre manual, pra credencial nunca passar por automação/chat:

```bash
aws iam create-access-key --user-name eso-dev-secrets-reader
# copie AccessKeyId e SecretAccessKey do output e rode:
kubectl create secret generic aws-secretsmanager-creds -n external-secrets \
  --from-literal=access-key=<AccessKeyId> \
  --from-literal=secret-access-key=<SecretAccessKey>
```

Pra rotacionar depois: `aws iam create-access-key` (novo), `kubectl create
secret ... --dry-run=client -o yaml | kubectl apply -f -` (substitui), depois
`aws iam delete-access-key` na antiga.

### 4. Instalar o ESO via Helm (versão pinada)

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --version 2.11.0 \
  -f values.yaml
```

Verifique: `kubectl get pods -n external-secrets` — 3 pods (`external-secrets`,
`external-secrets-cert-controller`, `external-secrets-webhook`) `1/1 Running`.

### 5. ClusterSecretStore

```bash
kubectl apply -f cluster-secret-store.yaml
kubectl get clustersecretstore aws-secrets-manager -o jsonpath='{.status.conditions}'
```

Deve responder `"status":"True","type":"Ready"`.

Se for replicar em outro ambiente com outro nome de usuário/prefixo, ajuste
`region`/`accessKeyIDSecretRef`/`secretAccessKeySecretRef` em
`cluster-secret-store.yaml` (ou copie o arquivo com outro `metadata.name`, ex.
`aws-secrets-manager-prod`, se os dois clusters/stores coexistirem).

### 6. Cada app declara seu próprio ExternalSecret

Não mexe nesta pasta — cada app cria seu `ExternalSecret` no próprio
diretório `k8s/`, referenciando o mesmo store e puxando o blob inteiro do
secret (`dataFrom.extract`, não campo a campo — assim não precisa editar o
`ExternalSecret` toda vez que uma chave nova entra no JSON da AWS):

```yaml
spec:
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: <app>-secrets
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: dev/<project>/<app_name>
```

Exemplo real (formato antigo, campo a campo — ver nota de migração no spec):
[`../k8s/external-secrets/external-secret.yaml`](../k8s/external-secrets/external-secret.yaml).

## O que foi validado (cluster local Rancher Desktop)

- `helm install` limpo, 3 pods `Running`.
- `ClusterSecretStore` → `Ready`.
- `ExternalSecret` do app-manb-ms → `SecretSynced`, Secret `crm-api-key`
  criado com a chave `API_KEY`.
- Pod do app-manb-ms lendo o valor via env var, **sem nenhuma credencial AWS
  própria** (`kubectl exec ... -- env | grep AWS_` vazio).

## Antes de usar em produção de verdade

- `values.yaml` está com defaults do chart — revisar `replicaCount`,
  `resources`, `podDisruptionBudget` (não validado além de um nó único local).
- Cofre de estado do Helm/kubeconfig de prod não é o mesmo deste laptop —
  repita os passos 1–5 contra o contexto/cluster de prod.
- Considerar rotação periódica da access key do usuário ESO (passo 3).
