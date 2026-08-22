SHELL := /bin/bash

.PHONY: preflight start health smoke stop cleanup destroy logs ps

preflight:
	bash scripts/preflight.sh

start:
	bash scripts/start.sh

health:
	bash scripts/health.sh

smoke:
	bash scripts/smoke.sh

stop:
	bash scripts/stop.sh

cleanup:
	bash scripts/cleanup.sh

destroy:
	bash scripts/cleanup.sh --delete-data

logs:
	docker compose --env-file .env -f docker-compose.astravector.yml logs -f astravector

ps:
	docker compose --env-file .env -f docker-compose.astravector.yml ps
