IMAGE ?= contact-app
TAG   ?= 0.1.0

.PHONY: venv test run docker
venv:
	python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt -r tests/requirements-dev.txt
test:
	. .venv/bin/activate && PYTHONPATH=. pytest -q tests/
run:
	. .venv/bin/activate && python app.py
docker:
	docker build -t $(IMAGE):$(TAG) .
