package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"flag"
	"fmt"
	"path/filepath"
	"strconv"
	"strings"

	realio "io/ioutil"
	realos "os"

	"code.cloudfoundry.org/cli/cf/configuration"
	"code.cloudfoundry.org/cli/cf/configuration/confighelpers"
	"code.cloudfoundry.org/cli/cf/configuration/coreconfig"
	"code.cloudfoundry.org/cli/plugin"
	"github.com/norman-abramovitz/cf-targets-plugin/diff"
	"github.com/norman-abramovitz/cf-targets-plugin/diff/myers"
)

type TargetsPlugin struct {
	configPath  string
	targetsPath string
	currentPath string
	suffix      string
	status      TargetStatus
}

type TargetStatus struct {
	currentHasName     bool
	currentName        string
	currentNeedsSaving bool
	currentNeedsUpdate bool
}

type RealOS struct{}
type OS interface {
	Exit(int)
	Mkdir(string, realos.FileMode)
	Remove(string)
	Symlink(string, string) error
	ReadDir(string) ([]realos.FileInfo, error)
	ReadFile(string) ([]byte, error)
	WriteFile(string, []byte, realos.FileMode) error
}

func (*RealOS) Exit(code int)                                  { realos.Exit(code) }
func (*RealOS) Mkdir(path string, mode realos.FileMode)        { realos.Mkdir(path, mode) }
func (*RealOS) Remove(path string)                             { realos.Remove(path) }
func (*RealOS) Symlink(target string, source string) error     { return realos.Symlink(target, source) }
func (*RealOS) ReadDir(path string) ([]realos.FileInfo, error) { return realio.ReadDir(path) }
func (*RealOS) ReadFile(path string) ([]byte, error)           { return realio.ReadFile(path) }
func (*RealOS) WriteFile(path string, content []byte, mode realos.FileMode) error {
	return realio.WriteFile(path, content, mode)
}

var os OS
var SemVerMajor string
var SemVerMinor string
var SemVerPatch string
var SemVerPrerelease string
var SemVerBuild string
var BuildDate string
var BuildVcsUrl string
var BuildVcsId string
var BuildVcsIdDate string
var GoArch string
var GoOs string

func getIntOrPanic(toInt string) int {
	theInt, err := strconv.Atoi(toInt)
	if err != nil {
		panic("unable to parse version: " + err.Error())
	}
	return theInt
}

func newTargetsPlugin() *TargetsPlugin {
	configPath, _ := confighelpers.DefaultFilePath()
	targetsPath := filepath.Join(filepath.Dir(configPath), "targets")
	os.Mkdir(targetsPath, 0700)
	return &TargetsPlugin{
		configPath:  configPath,
		targetsPath: targetsPath,
		currentPath: filepath.Join(targetsPath, "current"),
		suffix:      "." + filepath.Base(configPath),
	}
}

func (c *TargetsPlugin) GetMetadata() plugin.PluginMetadata {
	return plugin.PluginMetadata{
		Name: "cf-targets",
		Version: plugin.VersionType{
			Major: getIntOrPanic(SemVerMajor),
			Minor: getIntOrPanic(SemVerMinor),
			Build: getIntOrPanic(SemVerPatch),
		},
		Commands: []plugin.Command{
			{
				Name:     "targets",
				HelpText: "List available targets",
				UsageDetails: plugin.Usage{
					Usage: "cf targets",
				},
			},
			{
				Name:     "set-target",
				HelpText: "Set current target",
				UsageDetails: plugin.Usage{
					Usage: "cf set-target [-f] NAME",
					Options: map[string]string{
						"f": "replace the current target even if it has not been saved",
					},
				},
			},
			{
				Name:     "save-target",
				HelpText: "Save current target",
				UsageDetails: plugin.Usage{
					Usage: "cf save-target [-f] [NAME]",
					Options: map[string]string{
						"f": "save the target even if the specified name already exists",
					},
				},
			},
			{
				Name:     "delete-target",
				HelpText: "Delete a saved target",
				UsageDetails: plugin.Usage{
					Usage: "cf delete-target NAME",
				},
			},
		},
	}
}

func createBuildMeta(buildOs, buildArch, build string) string {
	p1 := strings.TrimSpace(buildOs)
	p2 := strings.TrimSpace(buildArch)
	p3 := strings.TrimSpace(build)
	if p1 == "" || p2 == "" {
		panic(fmt.Sprintf("Go meta data is missing one of its parts: %s, %s ", p1, p2))
	}
	b := strings.Join([]string{p1, p2}, ".")
	if p3 != "" {
		b += "." + p3
	}
	return b
}

func createSemVer(major, minor, patch, prerelease, build string) string {
	p1 := strings.TrimSpace(major)
	p2 := strings.TrimSpace(minor)
	p3 := strings.TrimSpace(patch)
	p4 := strings.TrimSpace(prerelease)
	p5 := strings.TrimSpace(build)
	if p1 == "" || p2 == "" || p3 == "" {
		panic(fmt.Sprintf("Semanic version is missing one of its parts: %s.%s.%s", p1, p2, p3))
	}

	sv := strings.Join([]string{p1, p2, p3}, ".")
	if p4 != "" {
		sv += "-" + p4
	}
	if p5 != "" {
		sv += "+" + p5
	}
	return sv
}

func main() {
	args := realos.Args[1:]
	if len(args) == 0 {
		bm := createBuildMeta(GoOs, GoArch, SemVerBuild)
		sv := createSemVer(SemVerMajor, SemVerMinor, SemVerPatch, SemVerPrerelease, bm)
		f := "%13v %v\n"
		fmt.Printf(f, "Version:", sv)
		fmt.Printf(f, "Build Date:", BuildDate)
		fmt.Printf(f, "VCS Url:", BuildVcsUrl)
		fmt.Printf(f, "VCS Id:", BuildVcsId)
		fmt.Printf(f, "VCS Id Date:", BuildVcsIdDate)

		fmt.Printf("\nThe code in the diff directory is copyrighted by The Go Authors.")
		fmt.Printf("\nThe copyrighted code and its LICENSE file can be found there.\n\n")
		fmt.Printf("Copyright 2009 The Go Authors.\n\n")

		fmt.Printf("Redistribution and use in source and binary forms, with or without\n")
		fmt.Printf("modification, are permitted provided that the following conditions are\n")
		fmt.Printf("met:\n\n")

		fmt.Printf("   * Redistributions of source code must retain the above copyright\n")
		fmt.Printf("     notice, this list of conditions and the following disclaimer.\n")
		fmt.Printf("   * Redistributions in binary form must reproduce the above\n")
		fmt.Printf("     copyright notice, this list of conditions and the following disclaimer\n")
		fmt.Printf("     in the documentation and/or other materials provided with the\n")
		fmt.Printf("     distribution.\n")
		fmt.Printf("   * Neither the name of Google LLC nor the names of its\n")
		fmt.Printf("     contributors may be used to endorse or promote products derived from\n")
		fmt.Printf("     this software without specific prior written permission.\n")
	}
	os = &RealOS{}
	plugin.Start(newTargetsPlugin())
}

func (c *TargetsPlugin) Run(cliConnection plugin.CliConnection, args []string) {
	defer func() {
		reason := recover()
		if code, ok := reason.(int); ok {
			os.Exit(code)
		} else if reason != nil {
			panic(reason)
		}
	}()

	c.checkStatus()
	if args[0] == "targets" {
		c.TargetsCommand(args)
	} else if args[0] == "set-target" {
		c.SetTargetCommand(args)
	} else if args[0] == "save-target" {
		c.SaveTargetCommand(args)
	} else if args[0] == "delete-target" {
		c.DeleteTargetCommand(args)
	}
}

func createRedaction(jsonMap map[string]interface{}, key string) string {
	var valueAssertion interface{}
	valueAssertion = jsonMap[key]
	currentSum := sha256.Sum256([]byte(valueAssertion.(string)))
	return fmt.Sprintf("REDACTED sha256(%x)", currentSum)
}

func (c *TargetsPlugin) showDiff(targetPath string) {
	var json_data_current map[string]interface{}
	var json_data_target map[string]interface{}
	var err error

	currentContent, err := os.ReadFile(c.currentPath)
	c.checkError(err)
	targetContent, err := os.ReadFile(targetPath)
	c.checkError(err)
	err = json.Unmarshal(currentContent, &json_data_current)
	c.checkError(err)
	err = json.Unmarshal(targetContent, &json_data_target)
	c.checkError(err)

	json_data_current["AccessToken"] = createRedaction(json_data_current, "AccessToken")
	json_data_target["AccessToken"] = createRedaction(json_data_target, "AccessToken")

	json_data_current["RefreshToken"] = createRedaction(json_data_current, "RefreshToken")
	json_data_target["RefreshToken"] = createRedaction(json_data_target, "RefreshToken")

	json_data_current["UAAOAuthClientSecret"] = createRedaction(json_data_current, "UAAOAuthClientSecret")
	json_data_target["UAAOAuthClientSecret"] = createRedaction(json_data_target, "UAAOAuthClientSecret")

	current, err := json.MarshalIndent(json_data_current, "", " ")
	c.checkError(err)
	target, err := json.MarshalIndent(json_data_target, "", " ")
	c.checkError(err)

	edits := myers.ComputeEdits(string(current), string(target))
	udiff, err := diff.ToUnified("Current", "Target", string(current), edits, 0)
	c.checkError(err)
	fmt.Println(udiff)
}

func (c *TargetsPlugin) TargetsCommand(args []string) {
	if len(args) != 1 {
		c.exitWithUsage("targets")
	}
	targets := c.getTargets()
	if len(targets) < 1 {
		fmt.Println("No targets have been saved yet. To save the current target, use:")
		fmt.Println("   cf save-target NAME")
	} else {
		for _, target := range targets {
			var qualifier string
			if c.isCurrent(target) {
				qualifier = "(current"
				if c.status.currentNeedsSaving {
					qualifier += ", modified"
				} else if c.status.currentNeedsUpdate {
					qualifier += "*"
				}
				qualifier += ")"
			}
			fmt.Println(target, qualifier)
		}
	}
}

func (c *TargetsPlugin) SetTargetCommand(args []string) {
	flagSet := flag.NewFlagSet("set-target", flag.ContinueOnError)
	force := flagSet.Bool("f", false, "force")
	err := flagSet.Parse(args[1:])
	if err != nil || len(flagSet.Args()) != 1 {
		c.exitWithUsage("set-target")
	}
	targetName := flagSet.Arg(0)
	targetPath := c.targetPath(targetName)
	if !c.targetExists(targetPath) {
		fmt.Println("Target", targetName, "does not exist.")
		panic(1)
	}
	if *force || !c.status.currentNeedsSaving {
		c.copyContents(targetPath, c.configPath)
		c.linkCurrent(targetPath)
	} else {
		fmt.Println("Your current target has not been saved. Use save-target first, or use -f to discard your changes.")
		c.showDiff(targetPath)
		panic(1)
	}
	fmt.Println("Set target to", targetName)
}

func (c *TargetsPlugin) SaveTargetCommand(args []string) {
	flagSet := flag.NewFlagSet("save-target", flag.ContinueOnError)
	force := flagSet.Bool("f", false, "force")
	err := flagSet.Parse(args[1:])
	if err != nil || len(flagSet.Args()) > 1 {
		c.exitWithUsage("save-target")
	}
	if len(flagSet.Args()) < 1 {
		c.SaveCurrentTargetCommand(*force)
	} else {
		c.SaveNamedTargetCommand(flagSet.Arg(0), *force)
	}
}

func (c *TargetsPlugin) SaveNamedTargetCommand(targetName string, force bool) {
	targetPath := c.targetPath(targetName)
	if force || !c.targetExists(targetPath) {
		c.copyContents(c.configPath, targetPath)
		c.linkCurrent(targetPath)
	} else {
		fmt.Println("Target", targetName, "already exists. Use -f to overwrite it.")
		panic(1)
	}
	fmt.Println("Saved current target as", targetName)
}

func (c *TargetsPlugin) SaveCurrentTargetCommand(force bool) {
	if !c.status.currentHasName {
		fmt.Println("Current target has not been previously saved. Please provide a name.")
		panic(1)
	}
	targetName := c.status.currentName
	targetPath := c.targetPath(targetName)
	if c.status.currentNeedsSaving && !force {
		fmt.Println("You've made substantial changes to the current target.")
		fmt.Println("Use -f if you intend to overwrite the target named", targetName, "or provide an alternate name")
		c.showDiff(c.configPath)
		panic(1)
	}
	c.copyContents(c.configPath, targetPath)
	fmt.Println("Saved current target as", targetName)
}

func (c *TargetsPlugin) DeleteTargetCommand(args []string) {
	if len(args) != 2 {
		c.exitWithUsage("delete-target")
	}
	targetName := args[1]
	targetPath := c.targetPath(targetName)
	if !c.targetExists(targetPath) {
		fmt.Println("Target", targetName, "does not exist")
		panic(1)
	}
	os.Remove(targetPath)
	if c.isCurrent(targetName) {
		os.Remove(c.currentPath)
	}
	fmt.Println("Deleted target", targetName)
}

func (c *TargetsPlugin) getTargets() []string {
	var targets []string
	files, _ := os.ReadDir(c.targetsPath)
	for _, file := range files {
		filename := file.Name()
		if strings.HasSuffix(filename, c.suffix) {
			targets = append(targets, strings.TrimSuffix(filename, c.suffix))
		}
	}
	return targets
}

func (c *TargetsPlugin) targetExists(targetPath string) bool {
	target := configuration.NewDiskPersistor(targetPath)
	return target.Exists()
}

func (c *TargetsPlugin) checkStatus() {
	currentConfig := configuration.NewDiskPersistor(c.configPath)
	currentTarget := configuration.NewDiskPersistor(c.currentPath)
	if !currentTarget.Exists() {
		os.Remove(c.currentPath)
		c.status = TargetStatus{false, "", true, false}
		return
	}

	name := c.getCurrent()

	configData := coreconfig.NewData()
	targetData := coreconfig.NewData()

	err := currentConfig.Load(configData)
	c.checkError(err)
	err = currentTarget.Load(targetData)
	c.checkError(err)

	// Ignore the access-token field, as it changes frequently
	needsUpdate := targetData.AccessToken != configData.AccessToken
	targetData.AccessToken = configData.AccessToken

	currentContent, err := configData.JSONMarshalV3()
	c.checkError(err)
	savedContent, err := targetData.JSONMarshalV3()
	c.checkError(err)
	c.status = TargetStatus{true, name, !bytes.Equal(currentContent, savedContent), needsUpdate}
}

func (c *TargetsPlugin) copyContents(sourcePath, targetPath string) {
	content, err := os.ReadFile(sourcePath)
	c.checkError(err)
	err = os.WriteFile(targetPath, content, 0600)
	c.checkError(err)
}

func (c *TargetsPlugin) linkCurrent(targetPath string) {
	os.Remove(c.currentPath)
	err := os.Symlink(targetPath, c.currentPath)
	c.checkError(err)
}

func (c *TargetsPlugin) targetPath(targetName string) string {
	return filepath.Join(c.targetsPath, targetName+c.suffix)
}

func (c *TargetsPlugin) checkError(err error) {
	if err != nil {
		fmt.Println("Error:", err)
		panic(1)
	}
}

func (c *TargetsPlugin) exitWithUsage(command string) {
	metadata := c.GetMetadata()
	for _, candidate := range metadata.Commands {
		if candidate.Name == command {
			fmt.Println("Usage: " + candidate.UsageDetails.Usage)
			panic(1)
		}
	}
}

func (c *TargetsPlugin) getCurrent() string {
	targetPath, err := filepath.EvalSymlinks(c.currentPath)
	c.checkError(err)
	return strings.TrimSuffix(filepath.Base(targetPath), c.suffix)
}

func (c *TargetsPlugin) isCurrent(target string) bool {
	return c.status.currentHasName && c.status.currentName == target
}
