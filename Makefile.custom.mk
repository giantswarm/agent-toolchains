##@ Toolchains

.PHONY: check
check: ## Build every toolchain and run the toolchain contract check on it.
	scripts/check-toolchains.sh

.PHONY: check-fixtures
check-fixtures: ## Prove the toolchain contract check on the fixture toolchains.
	scripts/toolchain-contract-fixtures.sh
