CF Targets Plugin
=================

[![Build Status](https://travis-ci.org/norman-abramovitz/cf-targets-plugin.svg?branch=master)](https://travis-ci.org/norman-abramovitz/cf-targets-plugin)

This plugin facilitates the use of multiple api targets with the Cloud Foundry CLI.

It originated from the need for a Go play project, and the realization that I was
frequently switching back and forth between development and various test environments,
using tricks like

```
CF_HOME=~/cf-development cf push my-app
CF_HOME=~/cf-production cf push my-app
```

This plugin makes switching a lot less painful by allowing you to save your currently
configured target using a name, then switching back to it by name at any point.


## Usage

Configure and save any number of named targets

```
$ cf api <development-target-url>
$ cf login
...
$ cf save-target development
```

Followed by

```
$ cf api <production-target-url>
$ cf login
...
$ cf save-target production
```

After saving targets, easily switch back and forth between them using:

```
$ cf set-target development
$ cf target
API Endpoint:   <development-target-url>
...
$ cf set-target production
$ cf target
API Endpoint:   <production-target-url>
...
```

View saved targets using

```
$ cf targets
development
production (current)
```

When there are changes that have not been saved, a unified diff of the changes will be shown.  For sensitive data, a
sha26 checksum is displayed instead.  The sha checksum makes for easier reading of the changes.

```
$ cf set-target test
Your current target has not been saved. Use save-target first, or use -f to discard your changes.
--- Current
+++ Target
@@ -3 +3 @@
- "AccessToken": "REDACTED sha256(9b421f0de41ed363fdfe936fcb915fd01be6938fd37302a632d5405e1e47f9c1)",
+ "AccessToken": "REDACTED sha256(9feb3a0a506c808b6e016436fc8e07fb3f393b5014799f40172bf430c4a4e679)",
@@ -6 +6 @@
- "ColorEnabled": "0",
+ "ColorEnabled": "1",
@@ -23 +23 @@
- "RefreshToken": "REDACTED sha256(957ad5c277daf6afcec1d0de6a2f051c645ed69c0e7693b51503b3b6e0e97ac6)",
+ "RefreshToken": "REDACTED sha256(c3b764a22604e32b77b7148df69b2c5b0ed2f3402d29d6da5c97eb60b623420b)",
@@ -28 +28 @@
-  "AllowSSH": false,
+  "AllowSSH": true,
``` 

## Installation
##### Install from CLI
  ```
  $ cf add-plugin-repo CF-Community https://plugins.cloudfoundry.org/
  $ cf install-plugin Targets -r CF-Community
  ```
  
  
##### Install from Source (need to have [Go](http://golang.org/dl/) installed)
  ```
  $ git clone ... 
  $ cd cf-targets-plugin
  # 
  $ make build
  $ cf install-plugin cf-targets-plugin
  or 
  $ make install
  ```

## Full Command List

| command | usage | description|
| :--------------- |:---------------| :------------|
|`targets`| `cf targets` |list all saved targets|
|`save-target`|`cf save-target [-f] [<name>]`|save the current target for later use|
|`set-target`|`cf set-target [-f] <name>`|restore a previously saved target|
|`delete-target`|`cf delete-target <name>`|delete a previously saved target|

## Extended Build Metadata

The extended build metadata is available by executing the plugin itself.

```
./cf-targets-plugin
```

## Release Engineering Information

### GMake targets for pipelining

Generate release artifacts in the ***releases*** directory.  Sha256 checksum files are
created for each artifact as well. The file ***repo-index.yaml*** file is created for
when we are ready to submit to the cf-plugins-repo.  The GOOS and GOARCH variables are 
are included by default onto the build metadata string.
```
gmake ci-release VERSION=<major.minor,patch> [SEMVER_PRERELEASE=<prerelease-metadata>] [SEMVER_BUILDMETA=<buid-metadata>]
```

Cleans up after the artifacts are copied 
```
gmake release-clean

```
### GMake targets for manual release engineering

You can use the pipelining targets, but for manual release engineering testing the following
additional targets can be used for release build testing.

Same as ci-release but the version information defaults to the latest tag.  The patch
version is incremented to avoid version confusion for actual releases and the prerelease is set to dev.  
The same GMake variables used on ci-release can be used on release-all
```
gmake release-all
```

## GMake targets for development engineering

In addtion to the release engineering targets, the following targets will build the artifact for your local
environment.   The built artifact is located in the repo top directory.  The install target will build and install
the plugin into your local cf command. The same GMake variables for release engineering are available for development
engineering.
```
gmake build
./cf-targets-plugin
cf install-plugin cf-targets-plugin -f
```
or
```
gmake install 
./cf-targets-plugin
cf plugins
```

Clean up the build or install target generated artifacts
```
gmake clean
```
