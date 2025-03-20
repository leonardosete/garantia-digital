#!/usr/bin/env bash
set -euo pipefail

################################################################################
# CONFIGURAÇÕES
################################################################################
AWS_ACCOUNT_ID="114284751948"

# -----------------------------------
# ROLE DO PIPELINE/TERRAFORM
# -----------------------------------
PIPELINE_ROLE_NAME="GitHubActionsTerraformRole"
GITHUB_REPO="leonardosete/garantia-digital"

# Nome da policy que dá acesso ao S3 do Terraform + Lambda + PassRole
PIPELINE_POLICY_NAME="PipelineTerraformPolicy"

# Bucket S3 usado pelo Terraform para armazenar o tfstate
S3_BUCKET="garantia-digital-terraform-state"

# -----------------------------------
# ROLE DO LAMBDA
# -----------------------------------
LAMBDA_ROLE_NAME="LambdaGarantiaDigitalRole"

################################################################################
# 1) CRIA / VERIFICA O OIDC PROVIDER (GITHUB ACTIONS)
################################################################################
echo "[1/6] Verificando ou criando OIDC Provider do GitHub Actions..."
PROVIDER_URL="https://token.actions.githubusercontent.com"

aws iam create-open-id-connect-provider \
  --url "$PROVIDER_URL" \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 || {
    echo "OIDC provider já existe ou ocorreu outro erro. Prosseguindo..."
  }

################################################################################
# 2) CRIA / ATUALIZA A ROLE DO PIPELINE (TRUST POLICY)
################################################################################
echo "[2/6] Configurando trust policy da Role \"$PIPELINE_ROLE_NAME\"..."

cat > pipeline-trust-policy.json <<EOF
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

PIPELINE_ROLE_ARN=""
set +e
PIPELINE_ROLE_EXISTS=$(aws iam get-role --role-name "$PIPELINE_ROLE_NAME" --query "Role.RoleName" --output text 2>/dev/null)
set -e

if [[ -z "$PIPELINE_ROLE_EXISTS" || "$PIPELINE_ROLE_EXISTS" == "None" ]]; then
  echo "A Role do Pipeline não existe. Criando..."
  PIPELINE_ROLE_ARN=$(aws iam create-role \
    --role-name "$PIPELINE_ROLE_NAME" \
    --assume-role-policy-document file://pipeline-trust-policy.json \
    --description "Role para GitHub Actions OIDC + Terraform" \
    --query 'Role.Arn' \
    --output text)
  echo "Role do Pipeline criada: $PIPELINE_ROLE_ARN"
else
  echo "A Role do Pipeline já existe. Atualizando trust policy..."
  aws iam update-assume-role-policy \
    --role-name "$PIPELINE_ROLE_NAME" \
    --policy-document file://pipeline-trust-policy.json
  PIPELINE_ROLE_ARN=$(aws iam get-role --role-name "$PIPELINE_ROLE_NAME" --query "Role.Arn" --output text)
  echo "Trust policy da Role do Pipeline atualizada."
fi

################################################################################
# 3) CRIA / ATUALIZA A POLICY DO PIPELINE (S3 + LAMBDA + PASSROLE)
################################################################################
echo "[3/6] Criando/atualizando política customizada do Pipeline..."

cat > pipeline-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateListBucket",
      "Effect": "Allow",
      "Action": [ "s3:ListBucket" ],
      "Resource": [ "arn:aws:s3:::$S3_BUCKET" ]
    },
    {
      "Sid": "TerraformStateObjects",
      "Effect": "Allow",
      "Action": [ "s3:GetObject", "s3:PutObject", "s3:DeleteObject" ],
      "Resource": [ "arn:aws:s3:::$S3_BUCKET/*" ]
    },
    {
      "Sid": "LambdaManagement",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:GetFunction",
        "lambda:DeleteFunction"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PassRoleToLambda",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::$AWS_ACCOUNT_ID:role/$LAMBDA_ROLE_NAME"
    }
  ]
}
EOF

PIPELINE_POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$PIPELINE_POLICY_NAME'].Arn" --output text)

if [[ -z "$PIPELINE_POLICY_ARN" || "$PIPELINE_POLICY_ARN" == "None" ]]; then
  # Cria a policy se não existir
  PIPELINE_POLICY_ARN=$(aws iam create-policy \
    --policy-name "$PIPELINE_POLICY_NAME" \
    --policy-document file://pipeline-policy.json \
    --query 'Policy.Arn' \
    --output text)
  echo "Policy do Pipeline criada: $PIPELINE_POLICY_ARN"
else
  echo "Policy $PIPELINE_POLICY_NAME já existe. Atualizando conteúdo..."
  aws iam create-policy-version \
    --policy-arn "$PIPELINE_POLICY_ARN" \
    --policy-document file://pipeline-policy.json \
    --set-as-default
  echo "Policy do Pipeline atualizada. ARN: $PIPELINE_POLICY_ARN"
fi

################################################################################
# 4) ANEXA A POLICY AO PIPELINE ROLE
################################################################################
echo "[4/6] Anexando a política ao Pipeline Role..."

ATTACHED_PIPELINE=$(aws iam list-attached-role-policies \
  --role-name "$PIPELINE_ROLE_NAME" \
  --query "AttachedPolicies[?PolicyArn=='$PIPELINE_POLICY_ARN'].PolicyArn" \
  --output text || true)

if [[ "$ATTACHED_PIPELINE" == "None" || -z "$ATTACHED_PIPELINE" ]]; then
  aws iam attach-role-policy \
    --role-name "$PIPELINE_ROLE_NAME" \
    --policy-arn "$PIPELINE_POLICY_ARN"
  echo "Policy $PIPELINE_POLICY_ARN anexada à Role $PIPELINE_ROLE_NAME."
else
  echo "Policy $PIPELINE_POLICY_ARN já estava anexada à Role $PIPELINE_ROLE_NAME."
fi

################################################################################
# 5) CRIA / VERIFICA A ROLE DO LAMBDA (FORA DO TERRAFORM)
################################################################################
echo "[5/6] Verificando se a Role do Lambda \"$LAMBDA_ROLE_NAME\" já existe..."

set +e
LAMBDA_ROLE_EXISTS=$(aws iam get-role --role-name "$LAMBDA_ROLE_NAME" --query "Role.RoleName" --output text 2>/dev/null)
set -e

if [[ -z "$LAMBDA_ROLE_EXISTS" || "$LAMBDA_ROLE_EXISTS" == "None" ]]; then
  echo "Role do Lambda não existe. Criando..."
  cat > lambda-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  LAMBDA_ROLE_ARN=$(aws iam create-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --assume-role-policy-document file://lambda-trust-policy.json \
    --description "Role do Lambda Garantia Digital" \
    --query 'Role.Arn' --output text)

  echo "Role do Lambda criada: $LAMBDA_ROLE_ARN"

  # Anexar AWSLambdaBasicExecutionRole (logs no CloudWatch)
  aws iam attach-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  echo "Anexada AWSLambdaBasicExecutionRole à role do Lambda."
else
  echo "A role do Lambda \"$LAMBDA_ROLE_NAME\" já existe. Pulando criação."
fi

################################################################################
# 6) FINAL
################################################################################
echo ""
echo "==============================================="
echo "[6/6] Pronto! Criação/atualização concluída."
echo "Role do Pipeline : $PIPELINE_ROLE_NAME"
echo "Policy do Pipeline: $PIPELINE_POLICY_NAME"
echo "Role do Lambda   : $LAMBDA_ROLE_NAME"
echo "==============================================="
echo "Use a role '$PIPELINE_ROLE_NAME' no GitHub Actions (role-to-assume)"
echo "E a role '$LAMBDA_ROLE_NAME' no 'aws_lambda_function' do Terraform."
echo "==============================================="
