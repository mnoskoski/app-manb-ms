# AWS Secrets Manager naming convention

## Problema
Precisamos de um padrão de nome pra secrets no AWS Secrets Manager que escale por 4 ambientes
(dev/test/uat/prod) e múltiplos microsserviços, definido *antes* de criar mais secrets — e que
mapeie de forma óbvia pra estrutura de IAM/ESO em dois clusters diferentes (dev/test/uat
compartilham um cluster on-prem; prod é um cluster à parte).

## Proposta

### Nome do secret
```
{env}/{project}/{app_name}
```
- `{env}`: `dev` | `test` | `uat` | `prod`
- `{project}`: agrupamento de produto/sistema (ex.: `crm`) — útil quando várias apps
  pertencem ao mesmo domínio/produto
- `{app_name}`: nome do microsserviço (ex.: `app-manb-ms`)

`/` no Secrets Manager não cria pasta de verdade — é só convenção de string usada pra
prefix-match em policies IAM (`secret:dev/*`).

### Um secret por app, não um secret por chave
O **valor** do secret é um blob JSON com todas as chaves daquele app:
```json
{
  "API_KEY": "...",
  "DB_PASSWORD": "...",
  "WEBHOOK_SECRET": "..."
}
```
Motivo: custo (Secrets Manager cobra por secret/mês, não por tamanho — 1 secret com 5 chaves é
mais barato que 5 secrets), menos ARNs pra gerenciar em IAM/ExternalSecret, atualização atômica.

**Quando quebrar em mais de um secret por app**: só quando duas chaves têm escopo de acesso ou
política de rotação genuinamente diferentes (ex.: senha de banco com rotação automática da AWS
vs. uma API key de terceiro). Nesse caso, `{env}/{project}/{app_name}/{concern}`.

### ExternalSecret: usar `dataFrom.extract`, não `data` por campo
Pra puxar o blob inteiro sem listar cada chave manualmente (evita ter que editar o
`ExternalSecret` toda vez que uma chave nova é adicionada no JSON da AWS):
```yaml
spec:
  dataFrom:
    - extract:
        key: dev/crm/app-manb-ms
```
Isso cria todas as chaves do JSON como chaves separadas no `Secret` do k8s automaticamente.

### IAM/ESO: uma identidade por cluster, não por ambiente
dev/test/uat compartilham cluster → compartilham blast radius → **uma identidade IAM só**,
escopada aos 3 prefixos:
```
eso-nonprod-secrets-reader → Resource: [dev/*, test/*, uat/*]
```
prod é cluster separado → identidade separada, nunca reaproveitada:
```
eso-prod-secrets-reader → Resource: [prod/*]
```
Cada cluster tem sua própria instalação do ESO (Helm release) e seu próprio
`ClusterSecretStore`, usando a credencial correspondente. Ver `external-secrets/README.md`
pra como rodar `bootstrap-iam.sh` pra cada caso.

### Namespace do k8s espelha o ambiente
No cluster compartilhado: namespaces `dev`, `test`, `uat` (em vez de tudo em `default`, que é
só como está hoje no cluster de laboratório). Cada `ExternalSecret` no namespace `X` referencia
o secret `X/{project}/{app_name}` — mapeamento 1:1 entre namespace e prefixo do secret, fácil
de auditar visualmente.

## Escopo
- `external-secrets/bootstrap-iam.sh` + geração de policy: já atualizado pra aceitar múltiplos
  prefixos (`SECRET_PREFIXES='dev/* test/* uat/*'`), suportando o caso nonprod compartilhado.
- Este documento define o padrão; **não migra** o secret existente (`dev/crm/API_key`) nem o
  `ExternalSecret` do app-manb-ms — fica como decisão separada, ver Fora de escopo.

## Fora de escopo (por enquanto)
- Migrar `dev/crm/API_key` → `dev/crm/app-manb-ms` (renomear o secret na AWS + atualizar o
  `ExternalSecret` pra `dataFrom.extract`). Não fizemos isso ainda — decisão do usuário.
- Provisionar o cluster de prod, o `eso-prod-secrets-reader` de verdade, ou o segundo
  `ClusterSecretStore` — não temos acesso a esse cluster nesta sessão.
- Namespaces `dev`/`test`/`uat` reais no cluster local — hoje tudo roda em `default` porque é
  só o cluster de laboratório.
- Enforcement automático (ex. OPA/Kyverno) impedindo um `ExternalSecret` no namespace `dev` de
  referenciar um secret `uat/...` — a policy IAM permite tecnicamente (mesma credencial cobre
  os 3 prefixos); a separação por namespace é convenção, não hard enforcement. Mencionar como
  possível endurecimento futuro.

## Notas de implementação
- `bootstrap-iam.sh` gera a policy via Python (array de `Resource`) em vez de um template
  `.tmpl` com `sed` — necessário pra suportar N prefixos corretamente sem escaping manual de
  JSON.
- Nome da policy por padrão continua `ESODevSecretsManagerRead` (mesma da já existente) pra não
  duplicar ao rodar sem parâmetros contra o usuário atual; passe `IAM_POLICY_NAME` explícito ao
  criar a identidade de nonprod/prod.
