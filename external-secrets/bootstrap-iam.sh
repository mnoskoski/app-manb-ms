#!/usr/bin/env bash
# Creates (or updates) the dedicated IAM user + least-privilege policy that
# the External Secrets Operator uses to read AWS Secrets Manager secrets.
# Safe to re-run. Does NOT create an access key and does NOT touch any k8s
# Secret — that step is manual on purpose (see README.md), so no AWS
# credential material ever passes through automation.
#
# One IAM identity per *cluster* (trust boundary), not per environment:
# dev/test/uat share one on-prem cluster, so they share one identity scoped
# to all three prefixes. prod is a separate cluster and always gets its own
# identity, scoped only to prod/*.
#
# Usage:
#   ./bootstrap-iam.sh                                                       # default: dev/*, eso-dev-secrets-reader
#   SECRET_PREFIXES='dev/* test/* uat/*' IAM_USER_NAME='eso-nonprod-secrets-reader' IAM_POLICY_NAME='ESONonProdSecretsManagerRead' ./bootstrap-iam.sh
#   SECRET_PREFIXES='prod/*' IAM_USER_NAME='eso-prod-secrets-reader' IAM_POLICY_NAME='ESOProdSecretsManagerRead' ./bootstrap-iam.sh
set -euo pipefail

IAM_USER_NAME="${IAM_USER_NAME:-eso-dev-secrets-reader}"
IAM_POLICY_NAME="${IAM_POLICY_NAME:-ESODevSecretsManagerRead}"
SECRET_PREFIXES="${SECRET_PREFIXES:-dev/*}" # space-separated, e.g. 'dev/* test/* uat/*'

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

echo "Account:         $AWS_ACCOUNT_ID"
echo "IAM user:        $IAM_USER_NAME"
echo "Policy name:     $IAM_POLICY_NAME"
echo "Secret prefixes: $SECRET_PREFIXES"

if aws iam get-user --user-name "$IAM_USER_NAME" >/dev/null 2>&1; then
  echo "IAM user $IAM_USER_NAME already exists, skipping create-user"
else
  aws iam create-user --user-name "$IAM_USER_NAME" \
    --tags Key=purpose,Value=external-secrets-operator
fi

POLICY_FILE="$(mktemp)"
trap 'rm -f "$POLICY_FILE"' EXIT

python3 - "$AWS_ACCOUNT_ID" "$SECRET_PREFIXES" >"$POLICY_FILE" <<'PYEOF'
import json
import sys

account_id, prefixes_raw = sys.argv[1], sys.argv[2]
resources = [
    f"arn:aws:secretsmanager:*:{account_id}:secret:{prefix}"
    for prefix in prefixes_raw.split()
]
policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ReadSecretsUnderPrefixes",
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
            ],
            "Resource": resources,
        }
    ],
}
print(json.dumps(policy, indent=2))
PYEOF

aws iam put-user-policy \
  --user-name "$IAM_USER_NAME" \
  --policy-name "$IAM_POLICY_NAME" \
  --policy-document "file://$POLICY_FILE"

echo
echo "Done. IAM user + policy are ready. Next (manual, see README.md):"
echo "  1. aws iam create-access-key --user-name $IAM_USER_NAME"
echo "  2. kubectl create secret generic aws-secretsmanager-creds -n external-secrets \\"
echo "       --from-literal=access-key=<AccessKeyId> --from-literal=secret-access-key=<SecretAccessKey>"
