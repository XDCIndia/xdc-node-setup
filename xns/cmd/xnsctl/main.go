package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
	"xns/internal/validator"
	"xns/pkg/render"
)

var rootCmd = &cobra.Command{
	Use:   "xnsctl",
	Short: "XNS 2.0 control plane CLI",
	Long:  `xnsctl manages XDC node specifications and renders deployment configs.`,
}

var validateCmd = &cobra.Command{
	Use:   "validate <spec-file>",
	Short: "Validate a YAML/JSON spec",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		spec, err := validator.ValidateFile(args[0])
		if err != nil {
			return fmt.Errorf("validation failed: %w", err)
		}
		fmt.Printf("OK: spec %q validated (network=%s client=%s role=%s)\n",
			spec.Name, spec.Network, spec.Client, spec.Role)
		return nil
	},
}

var renderCmd = &cobra.Command{
	Use:   "render <spec-file>",
	Short: "Render compose output to stdout",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		spec, err := validator.ValidateFile(args[0])
		if err != nil {
			return err
		}
		out, err := render.RenderCompose(spec)
		if err != nil {
			return fmt.Errorf("render failed: %w", err)
		}
		fmt.Print(out)
		return nil
	},
}

var planCmd = &cobra.Command{
	Use:   "plan <spec-file>",
	Short: "Show diff vs running config (stub)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		spec, err := validator.ValidateFile(args[0])
		if err != nil {
			return err
		}
		fmt.Printf("[plan] stub: would compare %q against running containers\n", spec.Name)
		return nil
	},
}

func init() {
	cobra.OnInitialize(initConfig)
	rootCmd.AddCommand(validateCmd)
	rootCmd.AddCommand(renderCmd)
	rootCmd.AddCommand(planCmd)
}

func initConfig() {
	viper.SetEnvPrefix("XNS")
	viper.AutomaticEnv()
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
