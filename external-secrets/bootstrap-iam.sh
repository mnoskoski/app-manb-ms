#!/usr/bin/env bash
# Creates (or updates) the dedicated IAM user + least-privilege policy that
# the External Secrets Operator uses to read AWS Secrets Manager secrets.
# Safe to re-run. Does NOT create an access key and does NOT touch any k8s
# Secret — that step is manual on purpose (see README.md), so no AWS
# credential material ever passes through automation.
#
# Usage:
#   ./bootstrap-iam.sh                          # defaults: dev/*, eso-dev-secrets-reader
#   SECRET_PREFIX='prod/*' IAM_USER_NAME='eso-prod-secrets-reader' ./bootstrap-iam.sh
set -euo pipefail

IAM_USER_NAME="${IAM_USER_NAME:-eso-dev-secrets-reader}"
IAM_POLICY_NAME="${IAM_POLICY_NAME:-ESODevSecretsManagerRead}"
SECRET_PREFIX="${SECRET_PREFIX:-dev/*}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

echo "Account:        $AWS_ACCOUNT_ID"
echo "IAM user:       $IAM_USER_NAME"
echo "Policy name:    $IAM_POLICY_NAME"
echo "Secret prefix:  $SECRET_PREFIX"

if aws iam get-user --user-name "$IAM_USER_NAME" >/dev/null 2>&1; then
  echo "IAM user $IAM_USER_NAME already exists, skipping create-user"
else
  aws iam create-user --user-name "$IAM_USER_NAME" \
    --tags Key=purpose,Value=external-secrets-operator Key=env,Value="${SECRET_PREFIX%/*}"
fi

POLICY_FILE="$(mktemp)"
trap 'rm -f "$POLICY_FILE"' EXIT
sed \
  -e "s/ACCOUNT_ID_PLACEHOLDER/$AWS_ACCOUNT_ID/" \
  -e "s#SECRET_PREFIX_PLACEHOLDER#$SECRET_PREFIX#" \
  "$SCRIPT_DIR/iam-policy.json.tmpl" > "$POLICY_FILE"

aws iam put-user-policy \
  --user-name "$IAM_USER_NAME" \
  --policy-name "$IAM_POLICY_NAME" \
  --policy-document "file://$POLICY_FILE"

echo
echo "Done. IAM user + policy are ready. Next (manual, see README.md):"
echo "  1. aws iam create-access-key --user-name $IAM_USER_NAME"
echo "  2. kubectl create secret generic aws-secretsmanager-creds -n external-secrets \\"
echo "       --from-literal=access-key=<AccessKeyId> --from-literal=secret-access-key=<SecretAccessKey>"
