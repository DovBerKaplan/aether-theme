# Aether: a Plasma 6 desktop layer (theme, island, toasts, dock, console, lens, desk). `make help` lists the targets.
SHELL := /bin/bash
GEN   := theme/generators
APPS  := island toasts dock console lens desk

.DEFAULT_GOAL := help
.PHONY: help all tokens theme fonts components install install-island install-apps install-login install-gestures install-overview direction-install zcode-rtl-install uninstall restore check clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-18s %s\n", $$1, $$2}'

all: theme components ## Generate the theme and build the island, toasts, dock, console, lens and desk

tokens: ## Regenerate the QML design tokens from theme/tokens.toml
	python3 $(GEN)/build_tokens_qml.py

theme: tokens ## Generate colors, Kvantum, Plasma theme, global themes, Konsole, wallpapers, login backgrounds
	python3 $(GEN)/gen_grain.py
	python3 $(GEN)/build_colors.py
	python3 $(GEN)/build_kvantum.py
	python3 $(GEN)/build_desktoptheme.py
	python3 $(GEN)/build_lnf_konsole.py
	python3 $(GEN)/gen_wallpaper.py
	python3 $(GEN)/gen_lock_wallpaper.py

fonts: ## Fetch Inter and JetBrainsMono Nerd Font into ~/.local/share/fonts (skips what is present)
	install/fonts.sh

components: ## Build aether-island, aether-toasts, aether-dock, aether-console, aether-lens and aether-desk (needs the Qt/KF6 dev packages, see docs/INSTALL.md)
	@for app in $(APPS); do \
	  cmake -S components/$$app -B components/$$app/build -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null && \
	  cmake --build components/$$app/build || exit 1; \
	done

install: ## Full install for the current user: theme, island, toasts, shortcuts, panel layout (backs up first)
	install/install.sh

install-island: ## Build and (re)start the six aether services (quick rebuild path)
	install/install-island.sh

install-apps: ## Dress the apps (Kvantum, Aurorae titlebar, Konsole, GTK, KDE Flatpaks) and keep them on the island's accent
	install/install-apps.sh

install-login: ## Install the login screen (asks for sudo)
	sudo install/install-sddm.sh

install-gestures: ## Install 3-finger touchpad gestures (needs the input group, see docs/INSTALL.md)
	system/gestures/install-gestures.sh

install-overview: ## Glass restyle for the KWin Overview tiles (asks for sudo; re-apply after kwin updates)
	sudo install/install-overview.sh

direction-install: ## Install per-app RTL/LTR launch rules (aether-direction)
	system/direction/install-direction.sh

zcode-rtl-install: ## Install the ZCode (Electron) RTL kit: Hebrew locale hint + DevTools port + desktop override
	system/zcode-rtl/install-zcode-rtl.sh

uninstall: ## Stop and remove all six aether services
	install/uninstall-island.sh

restore: ## Restore the KDE settings from the latest backup
	install/restore.sh

check: ## Syntax-check scripts, run the split-model test and build all six components
	@for f in install/*.sh system/*.sh system/aether-mode-sync system/gestures/*.sh system/direction/*.sh system/zcode-rtl/*.sh; do bash -n $$f || exit 1; done
	python3 -m py_compile $(GEN)/*.py system/shortcuts/*.py tools/*.py system/aether-accent-sync system/direction/aether-direction system/direction/aether-direction-run system/vibe/aether-vibe system/agents/aether-agent-run
	node --check system/zcode-rtl/zcode-rtl-inspect.mjs
	node --check system/zcode-rtl/zcode-rtl-apply.mjs
	node --check system/zcode-rtl/zcode-rtl-inject.mjs
	node components/console/tests/split-model.test.js
	python3 $(GEN)/build_tokens_qml.py --check
	@for s in ribbons mist aurora ink dune; do qsb6 --glsl "100 es,120,150" --hlsl 50 --msl 12 -o /dev/null plasmoids/org.aether.$$s/contents/shaders/$$s.frag || exit 1; done
	node -e "new Function(require('fs').readFileSync('system/layout.js','utf8'))"
	$(MAKE) components

clean: ## Remove generated and build output
	rm -rf theme/generated login/aether-lock/backgrounds $(addprefix components/,$(addsuffix /build,$(APPS)))
