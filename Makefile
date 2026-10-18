# Builds a CLAP plugin from src/ with Zig.
#
#   make            build the plugin bundle into build/
#   make test       run the Zig unit tests
#   make install    copy the plugin to your user CLAP folder
#   make clean      remove build/
#
# Override on the command line, e.g. `make OPTIMIZE=Debug`.

NAME     ?= ZigGain
OPTIMIZE ?= ReleaseFast
ZIG      ?= zig

CLAP_INCLUDE := third_party/clap/include
BUILD        := build
SOURCES      := $(wildcard src/*.zig)

UNAME := $(shell uname -s)

ifeq ($(UNAME),Darwin)
  # macOS wants a bundle: Foo.clap/Contents/{Info.plist,MacOS/Foo}
  PLUGIN      := $(BUILD)/$(NAME).clap
  BINARY      := $(PLUGIN)/Contents/MacOS/$(NAME)
  INSTALL_DIR ?= $(HOME)/Library/Audio/Plug-Ins/CLAP
else ifeq ($(UNAME),Linux)
  # Linux wants a plain shared object named *.clap
  PLUGIN      := $(BUILD)/$(NAME).clap
  BINARY      := $(PLUGIN)
  INSTALL_DIR ?= $(HOME)/.clap
else
  $(error Unsupported platform $(UNAME). Only macOS and Linux are wired up)
endif

.DELETE_ON_ERROR:
.PHONY: all test install uninstall clean
all: $(PLUGIN)

# src/clap.h includes <clap/clap.h>. Zig 0.17 has no @cImport, so we translate
# the header to Zig once and import the result as the module "clap".
$(BUILD)/clap.zig: src/clap.h $(wildcard $(CLAP_INCLUDE)/clap/*.h $(CLAP_INCLUDE)/clap/*/*.h)
	@mkdir -p $(BUILD)
	$(ZIG) translate-c -lc -I$(CLAP_INCLUDE) src/clap.h > $@

$(BINARY): $(SOURCES) $(BUILD)/clap.zig
	@mkdir -p $(dir $@)
	$(ZIG) build-lib -dynamic -lc -O $(OPTIMIZE) \
		--dep clap -Mroot=src/clap_entry.zig -Mclap=$(BUILD)/clap.zig \
		-femit-bin=$@ --cache-dir $(BUILD)/cache --global-cache-dir $(BUILD)/cache
	@rm -f $(BINARY).o

ifeq ($(UNAME),Darwin)
$(PLUGIN): $(BINARY) Info.plist.in
	sed -e 's/@NAME@/$(NAME)/g' Info.plist.in > $(PLUGIN)/Contents/Info.plist
	printf 'BNDL????' > $(PLUGIN)/Contents/PkgInfo
	codesign --force --sign - $(PLUGIN)
	@touch $(PLUGIN)
else
$(PLUGIN): $(BINARY)
endif

test:
	$(ZIG) test src/plugin.zig

install: $(PLUGIN)
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/$(notdir $(PLUGIN))
	cp -R $(PLUGIN) $(INSTALL_DIR)/

uninstall:
	rm -rf $(INSTALL_DIR)/$(notdir $(PLUGIN))

clean:
	rm -rf $(BUILD)
