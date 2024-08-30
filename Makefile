PROJECT        :=cf-targets-plugin
GOOS           :=$(shell go env GOOS)
GOARCH         :=$(shell go env GOARCH)
GOMODULECMD    :=main
RELEASE_ROOT   ?=releases
DEV_TEST_BUILD =./$(PROJECT)
TARGETS        ?=linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64

ifneq ($(VERSION),)
VERSION_SPLIT:=$(subst ., ,$(VERSION))
  ifneq ($(words $(VERSION_SPLIT)),3)
    $(error VERSION does not 3 parts $(VERSION))
  endif
else
VERSION_TAG:=$(shell git describe --tags --abbrev=0 | sed -e "s/^v//")
VERSION_SPLIT:=$(subst ., ,$(VERSION_TAG))
  ifneq ($(words $(VERSION_SPLIT)),3)
    $(error VERSION_TAG  does not 3 parts |$(words $(VERSION_SPLIT))|$(VERSION_TAG)|$(VERSION_SPLIT)|)
  endif
  VERSION_SPLIT:=$(wordlist 1, 2, $(VERSION_SPLIT)) $(shell echo $$(($(word 3,$(VERSION_SPLIT))+1)))
endif

IS_NOT_NUMBER:=$(shell echo $(VERSION_SPLIT) | sed -e 's/[0123456789]//g')

ifneq ($(words $(IS_NOT_NUMBER)), 0)
  $(error The version string contain non-numeric characters)
endif

SEMVER_MAJOR    ?=$(word 1,$(VERSION_SPLIT))
SEMVER_MINOR    ?=$(word 2,$(VERSION_SPLIT))
SEMVER_PATCH    ?=$(word 3,$(VERSION_SPLIT))
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

.PHONY: distbuild build require-% release-% ci-release clean distclean show-releases create-repo-index

build: BUILD_GO_LDFLAGS:=-ldflags="$(GO_LDFLAGS) -X '$(GOMODULECMD).GoOs=$(GOOS)' -X '$(GOMODULECMD).GoArch=$(GOARCH)'"

build: BUILD_RULE_CMD := CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) \
	                     go build $(BUILD_GO_LDFLAGS) -o $(DEV_TEST_BUILD)

build: clean
	@echo "Building $(DEV_TEST_BUILD)"
	$(BUILD_RULE_CMD)


install: build
	cf install-plugin -f $(DEV_TEST_BUILD)

require-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set"; \
		exit 1; \
	fi

RELEASES := $(foreach target,$(TARGETS),release-$(target)-$(PROJECT))

show-releases:
	@ls -lA $(RELEASE_ROOT)
	@echo ""

ci-release: require-VERSION release-all

release-all: release-clean distbuild $(RELEASES) create-repo-index show-releases

create-repo-index: $(RELEASE_ROOT)/repo-index.yml

$(RELEASE_ROOT)/repo-index.yml: $(RELEASES) generate-repo-index
	./generate-repo-index "$(RELEASE_ROOT)" "$(PROJECT)" "$(SEMVER_VERSION)" "$(BUILD_DATE)"

distbuild:
	@mkdir -p $(RELEASE_ROOT)

define build-target
release-$(1)/$(2)-$(PROJECT): RELEASE_GO_LDFLAGS:=-ldflags="$(GO_LDFLAGS) -X '$(GOMODULECMD).GoOs=$(1)' -X '$(GOMODULECMD).GoArch=$(2)'"

release-$(1)/$(2)-$(PROJECT): RELEASE_EXECUTABLE_BASE:=$(RELEASE_ROOT)/$(PROJECT)-$(SEMVER_VERSION)+$(1).$(2)$(if $(3),.$(3))

release-$(1)/$(2)-$(PROJECT): RELEASE_EXECUTABLE:=$$(RELEASE_EXECUTABLE_BASE)$(if $(patsubst windows,,$(1)),,.exe)

release-$(1)/$(2)-$(PROJECT): RELEASE_EXECUTABLE_SHA1:=$$(RELEASE_EXECUTABLE_BASE).sha1

release-$(1)/$(2)-$(PROJECT):
	@echo "Building $$(PROJECT) version $$(SEMVER_VERSION) for $(1) $(2) ..."
	@CGO_ENABLED=0 GOOS=$(1) GOARCH=$(2) go build -o $$(RELEASE_EXECUTABLE) $$(RELEASE_GO_LDFLAGS)
	@openssl sha1 -r $$(RELEASE_EXECUTABLE) > $$(RELEASE_EXECUTABLE_SHA1)
endef

$(foreach target,$(TARGETS), $(eval $(call build-target,$(word 1, $(subst /, ,$(target))),$(word 2, $(subst /, ,$(target))),$(SEMVER_BUILDMETA))))

clean:
	@rm -rf $(DEV_TEST_BUILD) 

release-clean:
	@rm -rf $(RELEASE_ROOT)/* 

distclean: clean release-clean

.DEFAULT_GOAL := ci-release
