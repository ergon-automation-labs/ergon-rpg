MIX_BIN ?= $(shell which mix 2>/dev/null || echo /Users/abby/.local/share/mise/shims/mix)
VERSION ?= $(shell grep 'version:' mix.exs | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
SCRIPTS_DIRECTORY ?= $(abspath $(CURDIR)/../scripts)
MIX ?= /Users/abby/.local/share/mise/shims/mix

.PHONY: setup help deps test credo dialyzer coverage check format clean release publish-release setup-hooks setup-db reset-db logs push-and-publish rpg-theme-cyberpunk rpg-session-start rpg-start-round rpg-next-turn rpg-spectate-help bump-version

help:
	@echo "RPG Bot"
	@echo ""
	@echo "Setup commands:"
	@echo "  make setup           - Set up project (deps.get + install git hooks + setup database)"
	@echo "  make setup-hooks     - Install git hooks for pre-push validation"
	@echo "  make setup-db        - Create and migrate test database (required for testing)"
	@echo "  make reset-db        - Drop and recreate test database (useful for troubleshooting)"
	@echo ""
	@echo "Development commands:"
	@echo "  make test            - Run all tests"
	@echo "  make credo           - Run linter"
	@echo "  make dialyzer        - Run static analysis"
	@echo "  make coverage        - Run tests with coverage"
	@echo "  make check           - Run all checks (test, credo, dialyzer)"
	@echo "  make format          - Format Elixir code"
	@echo "  make clean           - Clean build artifacts"
	@echo ""
	@echo "Operations (deployed server logs):"
	@echo "  make logs            - Tail server log with grc (auto-detected by repo name; make -C .. install-grc)"
	@echo ""
	@echo "Release commands:"
	@echo "  make release         - Build OTP release locally"
	@echo "  make publish-release - Build, package, and publish to GitHub"
	@echo ""
	@echo "Normal workflow:"
	@echo "  git push             - Fast compile+test validation"
	@echo "  make push-and-publish - Push then publish release asset"
	@echo ""
	@echo "RPG game control:"
	@echo "  make rpg-theme-cyberpunk  - Set cyberpunk theme with rules"
	@echo "  make rpg-session-start    - Start session with bot players"
	@echo "  make rpg-start-round SESSION_ID=... - Begin a round"
	@echo "  make rpg-next-turn SESSION_ID=...   - Advance turn (bot autoplay)"
	@echo "  make rpg-spectate-help    - Show spectate controls"
	@echo ""

setup: init deps setup-hooks setup-db
	@echo "✓ Setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Configure .env with your database settings (if needed)"
	@echo "  2. Run: make test"
	@echo "  3. Start developing!"
	@echo ""

setup-hooks:
	@git config core.hooksPath git-hooks
	@echo "✓ Git hooks installed (core.hooksPath = git-hooks)"

setup-db:
	@echo "Setting up test database..."
	@MIX_ENV=test $(MIX_BIN) ecto.create || true
	@MIX_ENV=test $(MIX_BIN) ecto.migrate
	@echo "✓ Test database created and migrations applied"

reset-db:
	@echo "⚠️  Resetting test database (dropping and recreating)..."
	@MIX_ENV=test $(MIX_BIN) ecto.drop || true
	@MIX_ENV=test $(MIX_BIN) ecto.create
	@MIX_ENV=test $(MIX_BIN) ecto.migrate
	@echo "✓ Test database reset complete"

init:
	@if [ ! -d .git ]; then git init; echo "Git initialized."; else echo "Git already initialized."; fi

compile:
	@LOG_FILE="/tmp/compile-rpg-$$(date +%s).log"; \
	echo "Compiling rpg and logging to $$LOG_FILE..."; \
	$(MIX) compile 2>&1 | tee "$$LOG_FILE"; \
	echo "✓ Compilation log: $$LOG_FILE"

deps:
	$(MIX_BIN) deps.get

compile:
	@LOG_FILE="/tmp/compile-rpg-$$(date +%s).log"; \
	echo "Compiling rpg and logging to $$LOG_FILE..."; \
	$(MIX) compile 2>&1 | tee "$$LOG_FILE"; \
	echo "✓ Compilation log: $$LOG_FILE"

test:
	$(MIX_BIN) test

credo:
	$(MIX_BIN) credo

dialyzer: deps
	$(MIX_BIN) dialyzer

coverage:
	$(MIX_BIN) coveralls

check: test credo
	@echo "All checks passed!"

format:
	$(MIX_BIN) format

clean:
	$(MIX_BIN) clean
	rm -rf _build cover

release:
	@echo "==============================================="
	@echo "Building OTP release"
	@echo "==============================================="
	MIX_ENV=prod $(MIX_BIN) release
	@echo ""
	@echo "✓ Release built successfully"
	@echo "Location: _build/prod/rel/rpg_bot/"
	@echo ""

publish-release: release
	@echo "==============================================="
	@echo "Publishing release to GitHub"
	@echo "==============================================="
	@echo ""
	@echo "Version: $(VERSION)"
	@echo "Creating release tarball..."
	@tar -czf rpg_bot-$(VERSION).tar.gz -C _build/prod/rel rpg_bot/
	@echo "✓ Tarball created: rpg_bot-$(VERSION).tar.gz"
	@echo ""
	@echo "Creating GitHub release v$(VERSION)..."
	@gh release create v$(VERSION) rpg_bot-$(VERSION).tar.gz \
		--title "Release v$(VERSION)" \
		--notes "RPG Bot Elixir release v$(VERSION). Download and deploy with Jenkins." \
		--draft=false
	@echo "✓ Release published to GitHub"
	@echo ""
	@echo "Next steps:"
	@echo "1. Jenkins will automatically detect the new release"
	@echo "2. Trigger deployment in Jenkins UI or wait for auto-deployment"
	@echo "3. Check deployment status: make jenkins-logs"
	@echo ""

push-and-publish:
	@git push && $(MAKE) publish-release

# --- RPG game control targets ---
NATS_SERVER := nats://localhost:4222

rpg-theme-cyberpunk:
	@nats request --server $(NATS_SERVER) rpg.theme.change '{"setting":"cyberpunk","tone":"gritty","mechanic":"hacking","rules":{"dice_notation":"1d20","action_types":["attack","hack","evade","buff","inspect","inspire"],"initiative_method":"roll"},"tenant_id":"00000000-0000-0000-0000-000000000001"}' --timeout 5s

rpg-session-start:
	@nats request --server $(NATS_SERVER) rpg.session.start '{"bot_ids":["gtd_bot","synapse","llm_bot"],"scene_description":"Neon-drenched alleyway. Three figures circle each other under a flickering hologram ad.","tenant_id":"00000000-0000-0000-0000-000000000001"}' --timeout 5s

rpg-start-round:
	@if [ -z "$(SESSION_ID)" ]; then \
	  echo "Error: SESSION_ID not set. Usage: make rpg-start-round SESSION_ID=e291bf79-..."; \
	  exit 1; \
	fi
	@nats request --server $(NATS_SERVER) rpg.turn.start_round '{"session_id":"$(SESSION_ID)","tenant_id":"00000000-0000-0000-0000-000000000001"}' --timeout 5s

rpg-next-turn:
	@if [ -z "$(SESSION_ID)" ]; then \
	  echo "Error: SESSION_ID not set. Usage: make rpg-next-turn SESSION_ID=e291bf79-..."; \
	  exit 1; \
	fi
	@nats request --server $(NATS_SERVER) rpg.turn.next '{"session_id":"$(SESSION_ID)","tenant_id":"00000000-0000-0000-0000-000000000001"}' --timeout 5s

rpg-spectate-help:
	@echo "RPG Spectate — Hearth TUI controls"
	@echo ""
	@echo "  Tab (x2)      - Switch to spectate panel"
	@echo "  n             - Advance to next turn (calls rpg.turn.next)"
	@echo "  N             - Start a new round (calls rpg.turn.start_round)"
	@echo "  q / Ctrl+C    - Quit"
	@echo ""
	@echo "Quick start:"
	@echo "  1. make rpg-theme-cyberpunk"
	@echo "  2. make rpg-session-start"
	@echo "  3. make rpg-start-round SESSION_ID=<id-from-step-2>"
	@echo "  4. Open hearth TUI, Tab to spectate, press n to watch bots play"

logs:
	@$(SCRIPTS_DIRECTORY)/tail_bot_log.sh
bump-version:
	@if [ -z "$(BUMP)" ]; then echo "Usage: make bump-version BUMP=major|minor|patch"; exit 1; fi
	@OLD=$$(grep 'version:' mix.exs | head -1 | sed -E 's/.*version: "([^"]+)".*/\1/'); \
	bash $(SCRIPTS_DIRECTORY)/bump_version.sh mix.exs $(BUMP) > /dev/null; \
	NEW=$$(grep 'version:' mix.exs | head -1 | sed -E 's/.*version: "([^"]+)".*/\1/'); \
	echo "✓ Bumped: $$OLD → $$NEW"

push: test compile credo
	@echo "✅ All validations passed"
	@echo "$$(date +%s)" > .push-validated
	@echo "✓ Proof-of-validation created"
	@$(MAKE) git-push


git-push:
	@git push origin main 2>&1 | tail -3
