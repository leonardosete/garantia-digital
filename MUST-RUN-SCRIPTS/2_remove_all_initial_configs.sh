#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# CONFIGURAÇÕES
##############################################################################
AWS_ACCOUNT_ID="114284751948"

# Nomes das roles / policies
PIPELINE_ROLE_NAME="GitHubActionsTerraformRole"
PIPELINE_POLICY_NAME="PipelineTerraformPolicy"
LAMBDA_ROLE_NAME="LambdaGarantiaDigitalRole"

# Bucket S3 do tfstate
S3_BUCKET="garantia-digital-terraform-state"

# Opcional: remover também o OIDC provider
OIDC_PROVIDER_URL="token.actions.githubusercontent.com"

echo "========================================================="
echo "SCRIPT DE TEARDOWN - REMOVENDO RECURSOS"
echo "Bucket S3            : $S3_BUCKET"
echo "Pipeline Role        : $PIPELINE_ROLE_NAME"
echo "Policy Pipeline      : $PIPELINE_POLICY_NAME"
echo "Lambda Role          : $LAMBDA_ROLE_NAME"
echo "Remover Lambdas que contenham: garantia-digital"
echo "OIDC Provider (opt.) : $OIDC_PROVIDER_URL"
echo "========================================================="


##############################################################################
# 1) REMOVER / ESVAZIAR O BUCKET S3
##############################################################################
echo "[1/7] Esvaziando e removendo o bucket S3 ($S3_BUCKET)..."

# A) Remove objetos (sem versionamento)
aws s3 rm "s3://$S3_BUCKET" --recursive || \
  echo "Falha ao remover objetos ou bucket vazio."

# B) Remover versões e delete markers (caso o bucket tenha versionamento habilitado)
echo "Removendo todas as versões do bucket (se estiver versionado)..."
VERSIONS_JSON=$(aws s3api list-object-versions --bucket "$S3_BUCKET" --output json 2>/dev/null || true)
if [ -n "$VERSIONS_JSON" ]; then
  VERSIONS=$(echo "$VERSIONS_JSON" | jq -r '.Versions[]?, .DeleteMarkers[]? | [.Key, .VersionId] | @tsv' || true)
  if [ -n "$VERSIONS" ]; then
    while IFS=$'\t' read -r key version_id; do
      echo "Excluindo versão do objeto: Key=$key, VersionId=$version_id"
      aws s3api delete-object --bucket "$S3_BUCKET" --key "$key" --version-id "$version_id" || true
    done <<< "$VERSIONS"
  fi
fi

# C) Excluir o bucket
echo "Tentando apagar o bucket $S3_BUCKET..."
aws s3api delete-bucket --bucket "$S3_BUCKET" || \
  echo "Falha ao deletar bucket $S3_BUCKET (talvez não exista ou haja objetos)."


##############################################################################
# 2) REMOVER TODAS AS FUNÇÕES LAMBDA QUE TENHAM "garantia-digital" NO NOME
##############################################################################
echo "[2/7] Buscando e removendo Lambdas que contenham 'garantia-digital'..."

FUNCTIONS=$(aws lambda list-functions --query "Functions[].FunctionName" --output text || true)
if [ -n "$FUNCTIONS" ]; then
  for fn in $FUNCTIONS; do
    # Ajuste a lógica abaixo se quiser "contém" ou "começa com"
    # Aqui usamos '*garantia-digital*' => "contém"
    # Se quiser que seja prefixo: [[ $fn == garantia-digital* ]]
    if [[ "$fn" == *garantia-digital* ]]; then
      echo "Excluindo Lambda: $fn"
      set +e
      aws lambda delete-function --function-name "$fn"
      LAMBDA_DEL_EXIT=$?
      set -e
      if [ "$LAMBDA_DEL_EXIT" -ne 0 ]; then
        echo "Falha ao deletar a Lambda Function $fn. Talvez não exista."
      fi
    fi
  done
else
  echo "Nenhuma função Lambda encontrada."
fi


##############################################################################
# 3) REMOVER A POLICY DO PIPELINE
##############################################################################
echo "[3/7] Removendo a policy $PIPELINE_POLICY_NAME e desvinculando da role $PIPELINE_ROLE_NAME..."

PIPELINE_POLICY_ARN=$(aws iam list-policies \
  --query "Policies[?PolicyName=='$PIPELINE_POLICY_NAME'].Arn" \
  --output text || true)

if [[ "$PIPELINE_POLICY_ARN" != "None" && -n "$PIPELINE_POLICY_ARN" ]]; then
  echo "Desvinculando $PIPELINE_POLICY_ARN da role $PIPELINE_ROLE_NAME (se estiver anexada)."
  aws iam detach-role-policy \
    --role-name "$PIPELINE_ROLE_NAME" \
    --policy-arn "$PIPELINE_POLICY_ARN" || true

  echo "Apagando versões antigas da policy (se houver)..."
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

  echo "Removendo a policy $PIPELINE_POLICY_NAME."
  aws iam delete-policy --policy-arn "$PIPELINE_POLICY_ARN" || \
    echo "Falha ao deletar a policy (talvez já removida)."
else
  echo "Policy $PIPELINE_POLICY_NAME não encontrada. Prosseguindo."
fi


##############################################################################
# 4) REMOVER A ROLE DO PIPELINE
##############################################################################
echo "[4/7] Removendo a role do pipeline $PIPELINE_ROLE_NAME..."
set +e
aws iam delete-role --role-name "$PIPELINE_ROLE_NAME"
ROLE_DEL_EXIT=$?
set -e
if [ "$ROLE_DEL_EXIT" -ne 0 ]; then
  echo "Falha ao deletar a role do pipeline. Talvez não exista, ou haja policies pendentes."
fi


##############################################################################
# 5) REMOVER A ROLE DO LAMBDA
##############################################################################
echo "[5/7] Removendo a role do Lambda $LAMBDA_ROLE_NAME..."
# A) listar e detach de todas as policies
LAM_ROLE_ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
  --role-name "$LAMBDA_ROLE_NAME" \
  --query "AttachedPolicies[].PolicyArn" \
  --output text 2>/dev/null || true)

if [ -n "$LAM_ROLE_ATTACHED_POLICIES" ] && [ "$LAM_ROLE_ATTACHED_POLICIES" != "None" ]; then
  for policy_arn in $LAM_ROLE_ATTACHED_POLICIES; do
    echo "Desvinculando $policy_arn da role $LAMBDA_ROLE_NAME"
    aws iam detach-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-arn "$policy_arn" || true
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
# 6) (OPCIONAL) REMOVER O OIDC PROVIDER
##############################################################################
echo "[6/7] (Opcional) Removendo OIDC provider se quiser..."
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
# 7) FIM
##############################################################################
echo "[7/7] TEARDOWN FINALIZADO!"
echo "========================================================="
echo "Recursos removidos (bucket, Lambdas, roles, policies)."
echo "========================================================="
