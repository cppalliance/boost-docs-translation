.PHONY: lint test check
lint:
	scripts/lint.sh

test:
	scripts/test.sh

check: lint test
