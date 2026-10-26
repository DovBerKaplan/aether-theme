# Aether: a Plasma 6 desktop layer (theme, island, toasts). `make help` lists the targets.
SHELL := /bin/bash
GEN   := theme/generators
APPS  := island toasts

.DEFAULT_GOAL := help
.PHONY: help all theme components install install-island install-login install-gestures uninstall restore check clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-18s %s\n", $$1, $$2}'

all: theme components ## Generate the theme and build the island and toasts

theme: ## Generate colors, Kvantum, Plasma theme, global themes, Konsole, wallpapers, login backgrounds
	python3 $(GEN)/gen_grain.py
	python3 $(GEN)/build_colors.py
	python3 $(GEN)/build_kvantum.py
	python3 $(GEN)/build_desktoptheme.py
	python3 $(GEN)/build_lnf_konsole.py
	python3 $(GEN)/gen_wallpaper.py
	python3 $(GEN)/gen_lock_wallpaper.py

components: ## Build aether-island and aether-toasts (needs the Qt/KF6 dev packages, see docs/INSTALL.md)
	@for app in $(APPS); do \
	  cmake -S components/$$app -B components/$$app/build -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null && \
	  cmake --build components/$$app/build || exit 1; \
	done

install: ## Full install for the current user: theme, island, toasts, shortcuts, panel layout (backs up first)
	install/install.sh

install-island: ## Build and (re)start only the island and toasts services
	install/install-island.sh

install-login: ## Install the login screen (asks for sudo)
	sudo install/install-sddm.sh

install-gestures: ## Install 3-finger touchpad gestures (needs the input group, see docs/INSTALL.md)
	system/gestures/install-gestures.sh

uninstall: ## Stop and remove the island and toasts services
	install/uninstall-island.sh

restore: ## Restore the KDE settings from the latest backup
	install/restore.sh

check: ## Syntax-check scripts and build both components
	@for f in install/*.sh system/*.sh system/gestures/*.sh; do bash -n $$f || exit 1; done
	python3 -m py_compile $(GEN)/*.py system/shortcuts/*.py tools/*.py
	node -e "new Function(require('fs').readFileSync('system/layout.js','utf8'))"
	$(MAKE) components

clean: ## Remove generated and build output
	rm -rf theme/generated login/aether-lock/backgrounds $(addprefix components/,$(addsuffix /build,$(APPS)))
