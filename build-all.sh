#!/bin/bash

BUILD=$(date -Iseconds -u)
PRERELEASE="dev"
VERSION_CORE=$(git describe --tags --abbrev=0 | sed 's/^v//')
VERSION_CORE=(${VERSION_CORE//./ })

if [[ "$1" = "release" ]] ; then
    PRERELEASE=""
    TAG="$2"
    : ${TAG:?"Usage: build_all.sh [release] [TAG]"}

    git rev-parse --verify --quiet $TAG > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        echo "$TAG exists, remove it or increment"
        exit 1
    fi
fi

declare LINUX64_SHA1 OSX_AMD64_SHA1 OSX_ARM64_SHA1 

function build_semver() {
    TAG="${VERSION_CORE[0]}.${VERSION_CORE[1]}.${VERSION_CORE[2]}"
    [[ -n ${PRERELEASE} ]] && TAG="${TAG}-${PRERELEASE}"
    # [[ -n ${BUILD} ]] && TAG="${TAG}+${BUILD}"
}

function build_for() {
    echo "Building plugin for $GOOS $GOARCH..."
    eval "${CHECKSUM}=\"\""

    VERSION_FLAGS="-X 'main.Major=${VERSION_CORE[0]}'"
    VERSION_FLAGS="${VERSION_FLAGS} -X 'main.Minor=${VERSION_CORE[1]}'" 
    VERSION_FLAGS="${VERSION_FLAGS} -X 'main.Patch=${VERSION_CORE[2]}'"  
    VERSION_FLAGS="${VERSION_FLAGS} -X 'main.PrRls=${PRERELEASE}'"  
    VERSION_FLAGS="${VERSION_FLAGS} -X 'main.Build=${BUILD}'"  
    VERSION_FLAGS="${VERSION_FLAGS} -X 'main.GoArch=${GOARCH}'"  
    VERSION_FLAGS="${VERSION_FLAGS} -X 'main.GoOs=${GOOS}'"

    CGO_ENABLED=0 GOARCH=${GOARCH} GOOS=${GOOS} go build -o ./bin/cf-targets-plugin-${GOOS}-${GOARCH} -ldflags "${VERSION_FLAGS}"
    if [[ $? -eq 0 ]]; then
        eval "${CHECKSUM}=\"$(openssl sha1 -r bin/cf-targets-plugin-${GOOS}-${GOARCH})\""
    else
        eval "${CHECKSUM}=\"cf-targets-plugin-${GOOS}-${GOARCH} failed to compile\""
    fi
}

mkdir -p bin
CHECKSUM="LINUX64_SHA1" GOOS=linux GOARCH=amd64 build_for

CHECKSUM="OSX_AMD64_SHA1" GOOS=darwin GOARCH=amd64 build_for

CHECKSUM="OSX_ARM64_SHA1" GOOS=darwin GOARCH=arm64 build_for

CHECKSUM="WIN64_SHA1" GOOS=windows GOARCH=amd64 build_for

build_semver

cat repo-index.yml |
sed -e "s:osx-amd64-sha1:$OSX_AMD64_SHA1:" -e "s:osx-arm64-sha1:$OSX_ARM64_SHA1:" \
    -e "s:win64-sha1:$WIN64_SHA1:" -e "s:linux64-sha1:$LINUX64_SHA1:" \
    -e "s:_TAG_:$TAG:" -e "s/_BUILD-TAG_/$BUILD/"

#Link local build to give developer easy access to the plugin for installing
localExecutable="bin/cf-targets-plugin-$(go env GOOS)-$(go env GOARCH)"
rm -f ./cf-targets-plugin 
[[ -x ${localExecutable} ]] && ln -s ${localExecutable} ./cf-targets-plugin

if [[ "$1" = "release" ]] ; then
    git commit -am "Build version $TAG"
    git tag -a $TAG
    echo "Tagged release, 'git push --tags' to move it to github, and copy the output above"
    echo "to the cli repo you plan to deploy in"
fi

