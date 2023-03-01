/*
Copyright © 2022 - 2023 SUSE LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"fmt"
	"go/ast"
	godoc "go/doc"
	"go/parser"
	"go/token"
	"os"
	"sort"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
	"github.com/spf13/cobra/doc"

	"github.com/rancher/elemental-cli/cmd"
)

func main() {
	rootCmd := cmd.NewRootCmd()
	for _, command := range []*cobra.Command{
		rootCmd,
		cmd.NewBuildDisk(rootCmd, false),
		cmd.NewBuildISO(rootCmd, false),
		cmd.NewCloudInitCmd(rootCmd),
		cmd.NewConvertDisk(rootCmd, false),
		cmd.NewInstallCmd(rootCmd, false),
		cmd.NewPullImageCmd(rootCmd, false),
		cmd.NewResetCmd(rootCmd, false),
		cmd.NewRunStage(rootCmd),
		cmd.NewUpgradeCmd(rootCmd, false),
		cmd.NewVersionCmd(rootCmd),
	} {
		// Disables the line AUTOGENERATED BY ... ON DATE
		command.DisableAutoGenTag = true
		err := doc.GenMarkdownTree(command, ".")
		if err != nil {
			fmt.Print(err)
			os.Exit(1)
		}
	}

	if err := generateExitCodes(); err != nil {
		fmt.Printf("error generating exit-codes: %v\n", err)
		os.Exit(1)
	}
}

func generateExitCodes() error {
	fset := token.NewFileSet()
	files := []*ast.File{
		mustParse(fset, "../pkg/error/exit-codes.go"),
	}
	p, err := godoc.NewFromFiles(fset, files, "github.com/rancher/elemental-cli")
	if err != nil {
		panic(err)
	}
	var (
		exitCodes []*ErrorCode
		used      map[int]bool
	)

	used = make(map[int]bool)

	for _, c := range p.Consts {
		// Cast it, its safe as these are constants
		v := c.Decl.Specs[0].(*ast.ValueSpec)
		val := v.Values[0].(*ast.BasicLit)
		code, _ := strconv.Atoi(val.Value)

		if _, ok := used[code]; ok {
			return fmt.Errorf("duplicate exit-code found: %v", code)
		}

		used[code] = true
		exitCodes = append(exitCodes, &ErrorCode{code: code, doc: c.Doc})
	}

	sort.Slice(exitCodes[:], func(i, j int) bool {
		return exitCodes[i].code < exitCodes[j].code
	})

	exitCodesFile, err := os.Create("elemental_exit-codes.md")

	if err != nil {
		fmt.Print(err)
		return err
	}

	defer func() {
		_ = exitCodesFile.Close()
	}()

	_, _ = exitCodesFile.WriteString("# Exit codes for elemental CLI\n\n\n")
	_, _ = exitCodesFile.WriteString("| Exit code | Meaning |\n")
	_, _ = exitCodesFile.WriteString("| :----: | :---- |\n")
	for _, code := range exitCodes {
		_, err = exitCodesFile.WriteString(fmt.Sprintf("| %d | %s|\n", code.code, strings.Replace(code.doc, "\n", "", 1)))
		if err != nil {
			return err
		}
	}

	return nil
}

func mustParse(fset *token.FileSet, filename string) *ast.File {
	f, err := parser.ParseFile(fset, filename, nil, parser.ParseComments)
	if err != nil {
		panic(err)
	}
	return f
}

type ErrorCode struct {
	code int
	doc  string
}
