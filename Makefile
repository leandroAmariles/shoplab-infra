# Orquesta el flujo local: Floci -> bootstrap del estado -> terraform apply.
# Los objetivos se completan en las tareas T019, T022, T033 y T036 de LAB-98.
.PHONY: up down bootstrap test test-integration scan

bootstrap:
	@bash scripts/bootstrap.sh
	@bash scripts/init-env.sh

up:
	@bash scripts/up.sh

down:
	@echo "pendiente: T022" && exit 1

test:
	@echo "pendiente: T036" && exit 1

test-integration:
	@echo "pendiente: T036" && exit 1

scan:
	@echo "pendiente: T033" && exit 1
