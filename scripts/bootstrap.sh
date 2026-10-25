#!/usr/bin/env bash
# Crea el bucket de estado remoto (módulo state) con backend local, y deja el entorno listo para init con S3.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BOOT_DIR="$ENV_DIR/bootstrap"
wait_for_emulator
log "bootstrap del estado ($ENV_NAME)"
terraform -chdir="$BOOT_DIR" init -input=false
terraform -chdir="$BOOT_DIR" apply -input=false -auto-approve -state="$BOOT_STATE" \
  -var "environment=$ENV_NAME" -var "emulator_endpoint=$EMULATOR_URL"
