#!/bin/bash

BUILD=$(date -Iseconds -u)
PRERELEASE="dev"
DATETAG=$(date -Idate -u)
echo DATETAG $DATETAG
VERSION_CORE=$(git describe --tags --abbrev=0 | sed 's/^v//')
VERSION_CORE=(${VERSION_CORE//./ })

if [[ "$1" = "release" ]] ; then
	TAG="$2"
	: ${TAG:?"Usage: build_all.sh [release] [TAG]"}

	git tag | grep $TAG > /dev/null 2>&1
	if [ $? -eq 0 ] ; then
		echo "$TAG exists, remove it or increment"
		exit 1
	else
		MAJOR=`echo $TAG | sed 's/^v//' | awk 'BEGIN {FS = "." } ; { printf $1;}'`
		MINOR=`echo $TAG | sed 's/^v//' | awk 'BEGIN {FS = "." } ; { printf $2;}'`
		PATCH=`echo $TAG | sed 's/^v//' | awk 'BEGIN {FS = "." } ; { printf $3;}'`

		`sed -i .bak -e "s/Major:.*/Major: $MAJOR,/" \
			-e "s/Minor:.*/Minor: $MINOR,/" \
			-e "s/Build:.*/Build: $PATCH,/" cf_targets.go`
	fi
fi

declare LINUX64_SHA1 OSX_AMD64_SHA1 OSX_ARM64_SHA1 
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

cat repo-index.yml |
sed -e "s:osx-amd64-sha1:$OSX_AMD64_SHA1:" -e "s:osx-arm64-sha1:$OSX_ARM64_SHA1:" \
    -e "s:win64-sha1:$WIN64_SHA1:" -e "s:linux64-sha1:$LINUX64_SHA1:" \
    -e "s:_TAG_:$TAG:" -e "s:_DATE-TAG_:$DATETAG:"

#Final build gives developer a plugin to install
localExecutable="bin/cf-targets-plugin-$(go env GOOS)-$(go env GOARCH)"
rm -f ./cf-targets-plugin 
[[ -x ${localExecutable} ]] && ln -s ${localExecutable} ./cf-targets-plugin

if [[ "$1" = "release" ]] ; then
	git commit -am "Build version $TAG"
	git tag $TAG
	echo "Tagged release, 'git push --tags' to move it to github, and copy the output above"
	echo "to the cli repo you plan to deploy in"
fi

