# Orquesta el flujo local (Floci -> bootstrap del estado -> terraform apply) y los controles del pipeline de CI.
# Cada objetivo delega en scripts/*.sh, que también se pueden ejecutar sin make. Las versiones de las herramientas
# salen de versions.env, la misma fuente que usa el workflow (LAB-99): `make check` reproduce lo que corre en CI.
include versions.env

.PHONY: up down bootstrap test test-integration scan \
	check check-tools fmt-check validate lint pins tf-test trivy plan smoke

bootstrap:
	@bash scripts/bootstrap.sh
	@bash scripts/init-env.sh

up:
	@bash scripts/up.sh

down:
	@bash scripts/down.sh

test:
	@bash scripts/test.sh

test-integration:
	@bash scripts/test-integration.sh

scan:
	@bash scripts/scan.sh

# --- Controles del pipeline (job `static` y `trivy` de .github/workflows/ci.yml) ---
check: check-tools fmt-check validate lint pins tf-test trivy

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

trivy:
	@bash scripts/trivy.sh

# Requieren Docker y varios minutos: no forman parte de `make check`.
plan:
	@bash scripts/plan.sh

smoke:
	@bash scripts/smoke.sh
