PROJECT        :=cf-targets-plugin
GOOS           :=$(shell go env GOOS)
GOARCH         :=$(shell go env GOARCH)
GOMODULECMD    :=main
RELEASE_ROOT   ?=release
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

GO_LDFLAGS = -ldflags="-X '$(GOMODULECMD).SemVerMajor=$(SEMVER_MAJOR)' \
	            -X '$(GOMODULECMD).SemVerMinor=$(SEMVER_MINOR)' \
	            -X '$(GOMODULECMD).SemVerPatch=$(SEMVER_PATCH)' \
	            -X '$(GOMODULECMD).SemVerPrerelease=$(SEMVER_PRERELEASE)' \
	            -X '$(GOMODULECMD).SemVerBuild=$(SEMVER_BUILDMETA)' \
	            -X '$(GOMODULECMD).BuildDate=$(BUILD_DATE)' \
	            -X '$(GOMODULECMD).BuildVcsUrl=$(BUILD_VCS_URL)' \
	            -X '$(GOMODULECMD).BuildVcsId=$(BUILD_VCS_ID)' \
		        -X '$(GOMODULECMD).BuildVcsIdDate=$(BUILD_VCS_ID_DATE)'"

SEMVER_VERSION := $(if $(SEMVER_MAJOR),$(SEMVER_MAJOR),$(error Missing SEMVER_MAJOR))
SEMVER_VERSION := $(SEMVER_VERSION)$(if $(SEMVER_MINOR),.$(SEMVER_MINOR),$(error Missing SEMVER_MINOR))
SEMVER_VERSION := $(SEMVER_VERSION)$(if $(SEMVER_PATCH),.$(SEMVER_PATCH),$(error Missing SEMVER_PATCH))
SEMVER_VERSION := $(SEMVER_VERSION)$(if $(SEMVER_PRERELEASE),-$(SEMVER_PRERELEASE))
SEMVER_VERSION := $(SEMVER_VERSION)$(if $(SEMVER_BUILDMETA),+$(SEMVER_BUILDMETA))

.PHONY: build test require-% release-% clean semver

build:
	CGO_ENABLED=0 go build $(GO_LDFLAGS) -o $(DEV_TEST_BUILD)

require-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set"; \
		exit 1; \
	fi

RELEASES := $(foreach target,$(TARGETS),release-$(target)-$(PROJECT))

show-releases:
	@ls -lA $(RELEASE_ROOT)
	@echo ""

release-all: $(RELEASES) show-releases

define build-target
release-$(1)/$(2)-$(PROJECT): # require-VERSION
	@echo "Building $(PROJECT) version $(SEMVER_VERSION) for $(1) $(2) ..."
	@CGO_ENABLED=0 GOOS=$(1) GOARCH=$(2) go build -o $(RELEASE_ROOT)/$(PROJECT)-$(SEMVER_VERSION)-$(1)-$(2)$(if $(patsubst windows,,$(1)),,.exe) $(GO_LDFLAGS)
endef

$(foreach target,$(TARGETS),$(eval $(call build-target,$(word 1, $(subst /, ,$(target))),$(word 2, $(subst /, ,$(target))))))

clean:
	rm -rf $(DEV_TEST_BUILD) $(RELEASE_ROOT)/* 

.DEFAULT_GOAL := release-all

# test:
#	ginkgo watch ./...
	
# test-ci:
#	ginkgo  ./...

# gen:
#	go generate ./...
# docker:
#	docker build -t $(docker_registry) .

# publish: docker
#	docker push $(docker_registry)

# fmt:
#	find . -name '*.go' | while read -r f; do \
#		gofmt -w -s "$$f"; \
#	done

# .DEFAULT_GOAL := docker

# .PHONY: go-mod docker-build docker-push docker test fmt