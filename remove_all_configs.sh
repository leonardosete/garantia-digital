#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# CONFIGURAÇÕES
##############################################################################
AWS_ACCOUNT_ID="114284751948"

# Recursos criados pelo setup
PIPELINE_ROLE_NAME="GitHubActionsTerraformRole"
PIPELINE_POLICY_NAME="PipelineTerraformPolicy"
LAMBDA_ROLE_NAME="LambdaGarantiaDigitalRole"
S3_BUCKET="garantia-digital-terraform-state"

# Opcional: remover também o OIDC provider do GitHub
OIDC_PROVIDER_URL="token.actions.githubusercontent.com"

echo "========================================================="
echo "SCRIPT DE TEARDOWN - REMOVENDO RECURSOS"
echo "Bucket S3            : $S3_BUCKET"
echo "Pipeline Role        : $PIPELINE_ROLE_NAME"
echo "Policy Pipeline      : $PIPELINE_POLICY_NAME"
echo "Lambda Role          : $LAMBDA_ROLE_NAME"
echo "OIDC Provider (opt.) : $OIDC_PROVIDER_URL"
echo "========================================================="

##############################################################################
# 1) REMOVER / ESVAZIAR O BUCKET S3
##############################################################################
echo "[1/6] Esvaziando e removendo o bucket S3 ($S3_BUCKET)..."
# Passo A: Esvaziar (remove todos os objetos do bucket)
aws s3 rm "s3://$S3_BUCKET" --recursive || \
  echo "Falha ao remover objetos ou bucket já vazio."

# Passo B: Excluir o bucket
aws s3api delete-bucket --bucket "$S3_BUCKET" || \
  echo "Falha ao deletar bucket $S3_BUCKET (talvez não exista)."

##############################################################################
# 2) REMOVER A POLICY DO PIPELINE
##############################################################################
echo "[2/6] Removendo a policy $PIPELINE_POLICY_NAME e desvinculando da role $PIPELINE_ROLE_NAME..."

# Achar ARN da policy
PIPELINE_POLICY_ARN=$(aws iam list-policies \
  --query "Policies[?PolicyName=='$PIPELINE_POLICY_NAME'].Arn" \
  --output text || true)

if [[ "$PIPELINE_POLICY_ARN" != "None" && -n "$PIPELINE_POLICY_ARN" ]]; then

  # Detach da role do Pipeline
  echo "Desvinculando $PIPELINE_POLICY_ARN da role $PIPELINE_ROLE_NAME (se estiver anexada)."
  aws iam detach-role-policy \
    --role-name "$PIPELINE_ROLE_NAME" \
    --policy-arn "$PIPELINE_POLICY_ARN" || true

  # Listar versões e apagar as antigas
  echo "Apagando versões antigas da policy (se houver) ..."
  VERSIONS_TO_DELETE=$(aws iam list-policy-versions \
    --policy-arn "$PIPELINE_POLICY_ARN" \
    --query "Versions[?IsDefaultVersion==\`false\`].VersionId" \
    --output text || true)

  for ver in $VERSIONS_TO_DELETE; do
    aws iam delete-policy-version \
      --policy-arn "$PIPELINE_POLICY_ARN" \
      --version-id "$ver" || true
    echo "Deletou versão antiga: $ver"
  done

  # Finalmente apagar a policy
  echo "Removendo a policy $PIPELINE_POLICY_NAME."
  aws iam delete-policy --policy-arn "$PIPELINE_POLICY_ARN" || \
    echo "Falha ao deletar a policy (talvez já removida)."

else
  echo "Policy $PIPELINE_POLICY_NAME não encontrada. Prosseguindo."
fi

##############################################################################
# 3) REMOVER A ROLE DO PIPELINE
##############################################################################
echo "[3/6] Removendo a role do pipeline $PIPELINE_ROLE_NAME..."

set +e
aws iam delete-role --role-name "$PIPELINE_ROLE_NAME"
ROLE_DEL_EXIT=$?
set -e

if [ "$ROLE_DEL_EXIT" -ne 0 ]; then
  echo "Falha ao deletar a role do pipeline. Talvez não exista, ou haja policies pendentes."
fi

##############################################################################
# 4) REMOVER A ROLE DO LAMBDA
##############################################################################
echo "[4/6] Removendo a role do Lambda $LAMBDA_ROLE_NAME..."

# Passo A: listar e detach de todas as policies anexadas
LAM_ROLE_ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
  --role-name "$LAMBDA_ROLE_NAME" \
  --query "AttachedPolicies[].PolicyArn" \
  --output text 2>/dev/null || true)

if [ -n "$LAM_ROLE_ATTACHED_POLICIES" ] && [ "$LAM_ROLE_ATTACHED_POLICIES" != "None" ]; then
  for policy_arn in $LAM_ROLE_ATTACHED_POLICIES; do
    echo "Desvinculando $policy_arn da role $LAMBDA_ROLE_NAME"
    aws iam detach-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-arn "$policy_arn"
  done
fi

set +e
aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"
LAMBDA_ROLE_DEL_EXIT=$?
set -e
if [ "$LAMBDA_ROLE_DEL_EXIT" -ne 0 ]; then
  echo "Falha ao deletar a role do Lambda. Talvez não exista ou ainda haja anexos pendentes."
fi

##############################################################################
# 5) (OPCIONAL) REMOVER O OIDC PROVIDER
##############################################################################
echo "[5/6] (Opcional) Removendo OIDC provider se quiser..."
OIDC_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/$OIDC_PROVIDER_URL"
echo "Tentando remover OIDC Provider $OIDC_ARN..."

set +e
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN"
OIDC_DEL_EXIT=$?
set -e

if [ "$OIDC_DEL_EXIT" -ne 0 ]; then
  echo "Falha ao remover OIDC $OIDC_ARN. Talvez esteja em uso ou não exista."
fi

##############################################################################
# 6) FIM
##############################################################################
echo "[6/6] TEARDOWN FINALIZADO!"
echo "========================================================="
echo "Recursos removidos (bucket, roles, policies)."
echo "========================================================="
