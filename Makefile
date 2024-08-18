PROJECT        :=cf-targets-plugin
GOOS           :=$(shell go env GOOS)
GOARCH         :=$(shell go env GOARCH)
GOMODULECMD    :=main
RELEASE_ROOT   ?=releases
DEV_TEST_BUILD =./$(PROJECT)
TARGETS        ?=linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64

SEMVER_MAJOR    ?=2
SEMVER_MINOR    ?=1
SEMVER_PATCH    ?=0
SEMVER_PRERELEASE ?=
SEMVER_BUILDMETA  ?=
BUILD_DATE        :=$(shell date -u -Iseconds)
BUILD_VCS_URL     :=$(shell git config --get remote.origin.url)
BUILD_VCS_ID      :=$(shell git log -n 1 --date=iso-strict-local --format="%h")
BUILD_VCS_ID_DATE :=$(shell TZ=UTC0 git log -n 1 --date=iso-strict-local --format='%ad')

build: SEMVER_PRERELEASE := dev

GO_LDFLAGS = -X '$(GOMODULECMD).SemVerMajor=$(SEMVER_MAJOR)' \
	         -X '$(GOMODULECMD).SemVerMinor=$(SEMVER_MINOR)' \
	         -X '$(GOMODULECMD).SemVerPatch=$(SEMVER_PATCH)' \
	         -X '$(GOMODULECMD).SemVerPrerelease=$(SEMVER_PRERELEASE)' \
	         -X '$(GOMODULECMD).SemVerBuild=$(SEMVER_BUILDMETA)' \
	         -X '$(GOMODULECMD).BuildDate=$(BUILD_DATE)' \
	         -X '$(GOMODULECMD).BuildVcsUrl=$(BUILD_VCS_URL)' \
	         -X '$(GOMODULECMD).BuildVcsId=$(BUILD_VCS_ID)' \
		     -X '$(GOMODULECMD).BuildVcsIdDate=$(BUILD_VCS_ID_DATE)'

# The build meta data is added when the build is done
#
SEMVER_VERSION := $(if $(SEMVER_MAJOR),$(SEMVER_MAJOR),$(error Missing SEMVER_MAJOR))
SEMVER_VERSION := $(SEMVER_VERSION)$(if $(SEMVER_MINOR),.$(SEMVER_MINOR),$(error Missing SEMVER_MINOR))
SEMVER_VERSION := $(SEMVER_VERSION)$(if $(SEMVER_PATCH),.$(SEMVER_PATCH),$(error Missing SEMVER_PATCH))
SEMVER_VERSION := $(SEMVER_VERSION)$(if $(SEMVER_PRERELEASE),-$(SEMVER_PRERELEASE))

.PHONY: distbuild build require-% release-% clean distclean show-releases

build: BUILD_RULE_CMD := CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) \
	                     go build -ldflags="$(GO_LDFLAGS) \
					     -X '$(GOMODULECMD).GoOs=$(GOOS)' \
					     -X '$(GOMODULECMD).GoArch=$(GOARCH)'" \
				   	     -o $(DEV_TEST_BUILD)

build: clean
	$(BUILD_RULE_CMD)

require-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set"; \
		exit 1; \
	fi

RELEASES := $(foreach target,$(TARGETS),release-$(target)-$(PROJECT))

show-releases:
	@ls -lA $(RELEASE_ROOT)
	@echo ""

sha1-releases:

release-all: release-clean distbuild $(RELEASES) show-releases

distbuild:
	@mkdir -p $(RELEASE_ROOT)

define build-target
release-$(1)/$(2)-$(PROJECT): RELEASE_GO_LDFLAGS:=-ldflags="$(GO_LDFLAGS) -X '$(GOMODULECMD).GoOs=$(1)' -X '$(GOMODULECMD).GoArch=$(2)'"

release-$(1)/$(2)-$(PROJECT): RELEASE_EXECUTABLE:=$(RELEASE_ROOT)/$(PROJECT)-$(SEMVER_VERSION)+$(1).$(2)$(if $(3),.$(3))$(if $(patsubst windows,,$(1)),,.exe)

release-$(1)/$(2)-$(PROJECT): RELEASE_SHA1_FILE:=$(RELEASE_ROOT)/$(PROJECT)-$(SEMVER_VERSION)+$(1).$(2)$(if $(3),.$(3)).sha1

release-$(1)/$(2)-$(PROJECT): # require-VERSION
	@echo "Building $$(PROJECT) version $$(SEMVER_VERSION) for $(1) $(2) ..."
	@CGO_ENABLED=0 GOOS=$(1) GOARCH=$(2) go build -o $$(RELEASE_EXECUTABLE) $$(RELEASE_GO_LDFLAGS)
	@openssl sha1 -r $$(RELEASE_EXECUTABLE) > $$(RELEASE_SHA1_FILE)
endef

$(foreach target,$(TARGETS), $(eval $(call build-target,$(word 1, $(subst /, ,$(target))),$(word 2, $(subst /, ,$(target))),$(SEMVER_BUILDMETA))))

clean:
	@rm -rf $(DEV_TEST_BUILD) 

release-clean:
	@rm -rf $(RELEASE_ROOT)/* 

distclean: clean release-clean

.DEFAULT_GOAL := release-all
