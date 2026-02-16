# Makefile for OpenTelemetry Collector & Jaeger Stack

.PHONY: help init-dev init-staging init-prod plan-dev plan-staging plan-prod apply-dev apply-staging apply-prod destroy-dev destroy-staging destroy-prod validate clean fmt

# Default target
help:
	@echo "OpenTelemetry Collector & Jaeger Stack - Terraform Management"
	@echo ""
	@echo "Available targets:"
	@echo "  Development:"
	@echo "    make init-dev      - Initialize Terraform for dev environment"
	@echo "    make plan-dev      - Plan changes for dev environment"
	@echo "    make apply-dev     - Apply changes to dev environment"
	@echo "    make destroy-dev   - Destroy dev environment"
	@echo ""
	@echo "  Staging:"
	@echo "    make init-staging  - Initialize Terraform for staging environment"
	@echo "    make plan-staging  - Plan changes for staging environment"
	@echo "    make apply-staging - Apply changes to staging environment"
	@echo "    make destroy-staging - Destroy staging environment"
	@echo ""
	@echo "  Production:"
	@echo "    make init-prod     - Initialize Terraform for production environment"
	@echo "    make plan-prod     - Plan changes for production environment"
	@echo "    make apply-prod    - Apply changes to production environment"
	@echo "    make destroy-prod  - Destroy production environment"
	@echo ""
	@echo "  Utilities:"
	@echo "    make validate      - Validate the telemetry stack health"
	@echo "    make fmt           - Format all Terraform files"
	@echo "    make clean         - Clean temporary files"
	@echo "    make kubeconfig    - Show current Kubernetes context"
	@echo ""
	@echo "  Quick Deploy:"
	@echo "    make deploy-dev    - Quick deploy to dev (init + apply)"
	@echo "    make deploy-staging - Quick deploy to staging (init + apply)"
	@echo ""

# Development Environment
init-dev:
	@echo "Initializing dev environment..."
	cd environments/dev && terraform init -upgrade

plan-dev:
	@echo "Planning dev environment..."
	cd environments/dev && terraform plan

apply-dev:
	@echo "Applying dev environment..."
	cd environments/dev && terraform apply

destroy-dev:
	@echo "Destroying dev environment..."
	cd environments/dev && terraform destroy

deploy-dev: init-dev apply-dev validate
	@echo "Dev environment deployed successfully!"

# Staging Environment
init-staging:
	@echo "Initializing staging environment..."
	cd environments/staging && terraform init -upgrade

plan-staging:
	@echo "Planning staging environment..."
	cd environments/staging && terraform plan

apply-staging:
	@echo "Applying staging environment..."
	cd environments/staging && terraform apply

destroy-staging:
	@echo "Destroying staging environment..."
	cd environments/staging && terraform destroy

deploy-staging: init-staging apply-staging validate
	@echo "Staging environment deployed successfully!"

# Production Environment
init-prod:
	@echo "Initializing production environment..."
	cd environments/production && terraform init -upgrade

plan-prod:
	@echo "Planning production environment..."
	cd environments/production && terraform plan

apply-prod:
	@echo "⚠️  WARNING: Applying to PRODUCTION ⚠️"
	@read -p "Are you sure? [yes/no]: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		cd environments/production && terraform apply; \
	else \
		echo "Cancelled."; \
	fi

destroy-prod:
	@echo "⚠️  WARNING: Destroying PRODUCTION ⚠️"
	@read -p "Type 'DELETE-PRODUCTION' to confirm: " confirm; \
	if [ "$$confirm" = "DELETE-PRODUCTION" ]; then \
		cd environments/production && terraform destroy; \
	else \
		echo "Cancelled."; \
	fi

# Utilities
validate:
	@echo "Validating telemetry stack..."
	@./scripts/validate.sh

fmt:
	@echo "Formatting Terraform files..."
	@terraform fmt -recursive .

clean:
	@echo "Cleaning temporary files..."
	@find . -name "*.tfplan" -type f -delete
	@find . -name ".terraform.lock.hcl" -type f -delete
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@echo "Cleaned!"

kubeconfig:
	@echo "Current Kubernetes context:"
	@kubectl config current-context
	@echo ""
	@kubectl cluster-info

# Port forwarding helpers
jaeger-ui:
	@echo "Port-forwarding Jaeger UI to http://localhost:16686"
	kubectl port-forward -n telemetry svc/jaeger-query 16686:16686

elasticsearch:
	@echo "Port-forwarding Elasticsearch to http://localhost:9200"
	kubectl port-forward -n telemetry svc/elasticsearch 9200:9200

# Monitoring helpers
logs-otel:
	kubectl logs -n telemetry -l app=otel-collector --tail=100 -f

logs-jaeger:
	kubectl logs -n telemetry -l app.kubernetes.io/component=query --tail=100 -f

logs-elasticsearch:
	kubectl logs -n telemetry -l app=elasticsearch --tail=100 -f

status:
	@echo "=== Pods ==="
	@kubectl get pods -n telemetry
	@echo ""
	@echo "=== Services ==="
	@kubectl get svc -n telemetry
	@echo ""
	@echo "=== HPA ==="
	@kubectl get hpa -n telemetry
	@echo ""
	@echo "=== PVC ==="
	@kubectl get pvc -n telemetry

# Test trace
test-trace:
	@echo "Sending test trace..."
	@kubectl run -it --rm otel-test --image=curlimages/curl --restart=Never -- \
		curl -X POST http://otel-collector.telemetry.svc.cluster.local:4318/v1/traces \
		-H "Content-Type: application/json" \
		-d '{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"makefile-test"}}]},"scopeSpans":[{"spans":[{"traceId":"5b8aa5a2d2c872e8321cf37308d69df2","spanId":"051581bf3cb55c13","name":"test-span","kind":1,"startTimeUnixNano":"1544712660000000000","endTimeUnixNano":"1544712661000000000"}]}]}]}'
	@echo ""
	@echo "Check Jaeger UI: http://localhost:16686 (run 'make jaeger-ui' first)"
