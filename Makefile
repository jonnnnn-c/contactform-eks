# Thin wrappers around scripts/deploy.py (the one canonical interface) plus a
# couple of dev helpers. Run `make help` to list everything.
SHELL := /bin/bash
NS    ?= contact-app
PY    := python3 scripts/deploy.py

.PHONY: help test lint setup-local local smoke aws aws-fresh aws-up aws-app aws-down

help:         ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

## --- Dev ---
test:         ## Run the Flask app unit tests
	cd app && PYTHONPATH=. python3 -m pytest -q tests/
lint:         ## Lint the Helm chart
	helm lint helm/contact-app -f helm/contact-app/values-eks.yaml --set app.image.repository=x --set secret.name=y

## --- Local RKE2 ---
setup-local:  ## Install RKE2 + tools and build/import the image (uses sudo)
	$(PY) setup-local
local:        ## Deploy the app to the local RKE2 cluster
	$(PY) local

## --- AWS EKS ---
aws:          ## Full AWS deploy: terraform + ansible + smoke test
	$(PY) aws
aws-fresh:    ## Full AWS deploy from a clean slate (destroy first)
	$(PY) aws --fresh
aws-up:       ## Provision AWS infra only (terraform)
	$(PY) aws-up
aws-app:      ## Deploy the app only (ansible + helm)
	$(PY) aws-app
aws-down:     ## Delete the NLB, then destroy all AWS infra
	$(PY) aws-down

## --- Verify ---
smoke:        ## Smoke-test the running service (override with NS=...)
	$(PY) -n $(NS) smoke
