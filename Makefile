.PHONY: tools-check docs-check

tools-check:
	./scripts/check-tools.sh

# docs-check gates every docs/diagram commit:
#  1. every .drawio file is valid XML
#  2. every .drawio file has an exported sibling .svg
#  3. the agent doc spine exists
docs-check:
	@for d in docs/diagrams/*.drawio; do \
		xmllint --noout "$$d" || exit 1; \
		svg="$${d%.drawio}.svg"; \
		[ -f "$$svg" ] || { echo "missing export: $$svg"; exit 1; }; \
	done
	@for f in START-HERE.md AGENTS.md CLAUDE.md docs/PROGRESS.md docs/IMPLEMENTATION-PLAN.md; do \
		[ -f "$$f" ] || { echo "missing spine file: $$f"; exit 1; }; \
	done
	@echo "docs-check OK"
