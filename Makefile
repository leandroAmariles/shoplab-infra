# Orquesta el flujo local (Floci -> bootstrap del estado -> terraform apply) y los controles del pipeline de CI.
# Cada objetivo delega en scripts/*.sh, que también se pueden ejecutar sin make. Las versiones de las herramientas
# salen de versions.env, la misma fuente que usa el workflow (LAB-99): `make check` reproduce lo que corre en CI.
include versions.env

.PHONY: up down stop destroy forward seed secrets quality bootstrap test test-integration scan \
	check check-tools fmt-check validate lint pins tf-test kustomize policies test-policies prom-rules test-ci-scripts trivy plan smoke

bootstrap:
	@bash scripts/bootstrap.sh
	@bash scripts/init-env.sh

# Crea el entorno o reanuda el que `make down` dejó detenido, y abre los túneles.
up:
	@bash scripts/up.sh

# Detiene túneles y contenedores sin borrar volúmenes. shoplab-helpdesk llama a `stop`: en una versión sin este target
# falla, en lugar de ejecutar el antiguo `down`, que borraba el entorno.
down stop:
	@bash scripts/stop.sh

# Borra el entorno: terraform destroy, contenedores, redes y el volumen de Floci.
destroy:
	@bash scripts/down.sh

# Expone el ingress en el host (port-forward en segundo plano); make up ya lo hace.
forward:
	@bash scripts/forward.sh

# Carga data/kb/*.md de shoplab-helpdesk en la base de conocimiento (POST /api/documents). make destroy borra la base: repetir tras volver a crearlo.
seed:
	@bash scripts/seed.sh

# Completa secrets.auto.tfvars con lo que falte (langfuse, litellm, clave `eval`) sin cambiar lo que ya hay ni imprimir valores;
# make up ya lo hace. Tras añadir claves nuevas, repetir make up para que Terraform las suba a Secrets Manager.
secrets:
	@bash scripts/ensure-secrets.sh

# Mide la calidad de las respuestas del asistente de dev (LAB-29). Necesita make up, make seed y los túneles (make forward).
# Argumentos de la medición: make quality ARGS="--run-id demo-1 --no-langfuse"
quality:
	@bash scripts/quality.sh $(ARGS)

test:
	@bash scripts/test.sh

test-integration:
	@bash scripts/test-integration.sh

scan:
	@bash scripts/scan.sh

# --- Controles del pipeline (job `static` y `trivy` de .github/workflows/ci.yml) ---
check: check-tools fmt-check validate lint pins tf-test kustomize policies test-policies prom-rules test-ci-scripts trivy

check-tools:
	@bash scripts/check-tools.sh

fmt-check:
	@bash scripts/test.sh fmt

validate:
	@bash scripts/test.sh validate

lint:
	@bash scripts/lint.sh

pins:
	@bash scripts/test.sh checks

tf-test:
	@bash scripts/test.sh modules

kustomize:
	@bash scripts/kustomize-build.sh

policies: kustomize
	@bash scripts/policies.sh

test-policies:
	@bash scripts/tests/policy-check.test.sh

# Decisión de omitir la prueba de humo en el commit automático de despliegue de dev (sin emulador ni herramientas extra).
test-ci-scripts:
	@bash scripts/tests/ensure-secrets.test.sh

# Reglas de alerta de los servicios (LAB-102): promtool check + test rules sobre la PrometheusRule renderizada.
prom-rules: kustomize
	@bash scripts/prom-rules.sh

trivy:
	@bash scripts/trivy.sh

# Requieren Docker y varios minutos: no forman parte de `make check`.
plan:
	@bash scripts/plan.sh

smoke:
	@bash scripts/smoke.sh
