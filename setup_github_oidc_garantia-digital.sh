#!/usr/bin/env bash
set -euo pipefail

################################################################################
# CONFIGURAÇÕES
################################################################################
AWS_ACCOUNT_ID="114284751948"
ROLE_NAME="GitHubActionsTerraformRole"
GITHUB_REPO="leonardosete/garantia-digital"
S3_BUCKET="garantia-digital-terraform-state"
CUSTOM_POLICY_NAME="TerraformStateS3Policy"

################################################################################
# 1) CRIA / VERIFICA OIDC PROVIDER
################################################################################
echo "[1/5] Criando (ou verificando) OIDC Provider..."
PROVIDER_URL="https://token.actions.githubusercontent.com"

aws iam create-open-id-connect-provider \
    --url "$PROVIDER_URL" \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 || {
      echo "OIDC provider já existe ou ocorreu outro erro. Prosseguindo..."
    }

################################################################################
# 2) CRIA / ATUALIZA A ROLE COM TRUST POLICY
################################################################################
echo "[2/5] Configurando trust policy da Role \"$ROLE_NAME\"..."

cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:$GITHUB_REPO:*"
        },
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

ROLE_ARN=""
set +e
ROLE_EXISTS=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.RoleName" --output text 2>/dev/null)
set -e

if [[ -z "$ROLE_EXISTS" || "$ROLE_EXISTS" == "None" ]]; then
    echo "Role não existe. Criando..."
    ROLE_ARN=$(aws iam create-role \
      --role-name "$ROLE_NAME" \
      --assume-role-policy-document file://trust-policy.json \
      --description "Role para GitHub Actions OIDC + Terraform" \
      --query 'Role.Arn' \
      --output text)
    echo "Role criada com ARN: $ROLE_ARN"
else
    echo "Role já existe. Atualizando trust policy..."
    aws iam update-assume-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-document file://trust-policy.json
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text)
    echo "Trust policy atualizada."
fi

################################################################################
# 3) CRIA / ATUALIZA A POLÍTICA CUSTOMIZADA DE ACESSO AO S3
################################################################################
echo "[3/5] Criando política customizada de acesso ao S3 (se não existir)..."

cat > custom-s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::$S3_BUCKET"]
    },
    {
      "Sid": "AllowCRUDOnObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": ["arn:aws:s3:::$S3_BUCKET/*"]
    }
  ]
}
EOF

POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$CUSTOM_POLICY_NAME'].Arn" --output text)
if [[ -z "$POLICY_ARN" || "$POLICY_ARN" == "None" ]]; then
  POLICY_ARN=$(aws iam create-policy \
    --policy-name "$CUSTOM_POLICY_NAME" \
    --policy-document file://custom-s3-policy.json \
    --query 'Policy.Arn' --output text)
  echo "Policy customizada criada com ARN: $POLICY_ARN"
else
  echo "Policy $CUSTOM_POLICY_NAME já existe. Atualizando conteúdo..."
  aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document file://custom-s3-policy.json \
    --set-as-default
  echo "Policy atualizada. ARN: $POLICY_ARN"
fi

################################################################################
# 4) ANEXA A POLÍTICA PERSONALIZADA À ROLE (SE NÃO ESTIVER ANEXADA)
################################################################################
echo "[4/5] Anexando política customizada na Role..."

ATTACHED_CUSTOM=$(aws iam list-attached-role-policies \
  --role-name "$ROLE_NAME" \
  --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN'].PolicyArn" \
  --output text || true)

if [[ "$ATTACHED_CUSTOM" == "None" || -z "$ATTACHED_CUSTOM" ]]; then
  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN"
  echo "Policy $POLICY_ARN anexada com sucesso à Role $ROLE_NAME."
else
  echo "Policy $POLICY_ARN já estava anexada à Role $ROLE_NAME."
fi

################################################################################
# (OPCIONAL) 5) ANEXAR OU REMOVER OUTRAS POLÍTICAS
################################################################################
# Exemplo: anexa AdministratorAccess (cuidado em produção)
#
# ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"
# ATTACHED_ADMIN=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN'].PolicyArn" --output text || true)
# if [[ "$ATTACHED_ADMIN" == "None" || -z "$ATTACHED_ADMIN" ]]; then
#   aws iam attach-role-policy \
#     --role-name "$ROLE_NAME" \
#     --policy-arn "$ADMIN_POLICY_ARN"
#   echo "Policy $ADMIN_POLICY_ARN anexada."
# else
#   echo "Policy $ADMIN_POLICY_ARN já anexada."
# fi

echo "[5/5] Finalizado!"
echo "===================================="
echo "Role ARN: $ROLE_ARN"
echo "Use esse ARN no seu GitHub Actions com 'role-to-assume'."
echo "===================================="
