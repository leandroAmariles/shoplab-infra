# Orquesta el flujo local: Floci -> bootstrap del estado -> terraform apply.
# Cada objetivo delega en scripts/*.sh, que también se pueden ejecutar sin make.
.PHONY: up down bootstrap test test-integration scan

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
