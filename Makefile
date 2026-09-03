.PHONY: tools-check actions-check docs-check helm-test

tools-check:
	./scripts/check-tools.sh

actions-check:
	./scripts/check-github-actions.sh

# One local entry point for the same Helm render contracts enforced in CI.
helm-test:
	python3 -m py_compile scripts/test_helm_render.py
	python3 scripts/test_helm_render.py
	bash -n scripts/test-p14-resource-right-sizing.sh
	./scripts/test-p14-resource-right-sizing.sh

# docs-check gates every docs/diagram commit:
#  1. every .drawio file is valid XML
#  2. every .drawio file has an exported sibling .svg
#  3. the agent doc spine exists
#  4. every external GitHub Action is pinned to an immutable commit
docs-check: actions-check
	@for d in docs/diagrams/*.drawio; do \
		xmllint --noout "$$d" || exit 1; \
		svg="$${d%.drawio}.svg"; \
		[ -f "$$svg" ] || { echo "missing export: $$svg"; exit 1; }; \
	done
	@for f in START-HERE.md AGENTS.md CLAUDE.md docs/PROGRESS.md docs/IMPLEMENTATION-PLAN.md; do \
		[ -f "$$f" ] || { echo "missing spine file: $$f"; exit 1; }; \
	done
	@echo "docs-check OK"
