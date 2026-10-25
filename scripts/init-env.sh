#!/usr/bin/env bash
# Inicializa el entorno raíz con el backend S3 del emulador; la clave del estado depende del ambiente.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

terraform -chdir="$ENV_DIR" init -input=false -reconfigure \
  -backend-config="bucket=shoplab-tfstate-$ENV_NAME" \
  -backend-config="key=$ENV_NAME/terraform.tfstate" \
  -backend-config="endpoints={s3=\"$EMULATOR_URL\"}"
