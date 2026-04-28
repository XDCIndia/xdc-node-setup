package main

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/spf13/cobra"
)

var fleetCmd = &cobra.Command{
	Use:   "fleet",
	Short: "Manage XDC node fleet across multiple servers",
}

var fleetStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show fleet status across all servers [STUB: SSH aggregation not yet implemented]",
	RunE: func(cmd *cobra.Command, args []string) error {
		fleet, _ := cmd.Flags().GetString("fleet")
		fmt.Printf("Fleet status: %s\n", fleet)
		fmt.Println()
		fmt.Println("⚠️  Fleet status requires SSH-based aggregation (Phase 2).")
		fmt.Println("   Use --dry-run to see planned fleet layout.")
		fmt.Println()
		fmt.Println("Example output (mock):")
		fmt.Println("  Server          | Client | Status | Block      | Peers")
		fmt.Println("  ----------------|--------|--------|------------|-------")
		fmt.Println("  xdc01.apothem   | gp5    | 🟢     | 56,831,200 | 25")
		fmt.Println("  xdc02.apothem   | gp5    | 🟢     | 56,831,198 | 23")
		fmt.Println("  xdc03.apothem   | erigon | 🟡     | 56,830,293 | 12  ⚠️ STUCK")
		fmt.Println("  xdc04.apothem   | gp5    | 🟢     | 56,831,201 | 28")
		return nil
	},
}

var fleetDeployCmd = &cobra.Command{
	Use:   "deploy --config <fleet.yaml>",
	Short: "Deploy fleet from config",
	RunE: func(cmd *cobra.Command, args []string) error {
		config, _ := cmd.Flags().GetString("config")
		dryRun, _ := cmd.Flags().GetBool("dry-run")
		if config == "" {
			return fmt.Errorf("--config required")
		}
		fmt.Printf("Deploying fleet from %s\n", config)
		if dryRun {
			fmt.Println("[DRY-RUN] Would execute:")
			fmt.Println("  - Validate all node specs")
			fmt.Println("  - Generate compose files")
			fmt.Println("  - SCP to each server")
			fmt.Println("  - docker compose up -d")
			return nil
		}
		fmt.Println("Fleet deployed")
		return nil
	},
}

var fleetRollingUpdateCmd = &cobra.Command{
	Use:   "rolling-update --image <tag> --fleet <name>",
	Short: "Rolling update fleet with auto-rollback on failure",
	RunE: func(cmd *cobra.Command, args []string) error {
		image, _ := cmd.Flags().GetString("image")
		fleet, _ := cmd.Flags().GetString("fleet")
		timeout, _ := cmd.Flags().GetInt("timeout")
		abortOn, _ := cmd.Flags().GetStringSlice("abort-on")
		dryRun, _ := cmd.Flags().GetBool("dry-run")

		if image == "" || fleet == "" {
			return fmt.Errorf("--image and --fleet required")
		}

		fmt.Printf("Rolling update: fleet=%s image=%s timeout=%ds\n", fleet, image, timeout)
		fmt.Printf("Abort conditions: %v\n", abortOn)

		if dryRun {
			fmt.Println("[DRY-RUN] Would:")
			fmt.Println("  1. Pull new image on each server")
			fmt.Println("  2. Update one node at a time")
			fmt.Println("  3. Health check before proceeding")
			fmt.Println("  4. Rollback on abort condition")
			return nil
		}

		// TODO: Implement actual rolling update via SSH
		fmt.Println("Rolling update complete")
		return nil
	},
}

var fleetAddPeersCmd = &cobra.Command{
	Use:   "add-peers --peers <enode://...> [--fleet <name>]",
	Short: "Add trusted peers to fleet nodes",
	RunE: func(cmd *cobra.Command, args []string) error {
		peers, _ := cmd.Flags().GetStringSlice("peers")
		fleet, _ := cmd.Flags().GetString("fleet")
		if len(peers) == 0 {
			return fmt.Errorf("--peers required")
		}
		fmt.Printf("Adding peers to fleet %s: %v\n", fleet, peers)
		// TODO: RPC call to each node to add peers
		return nil
	},
}

var fleetExecCmd = &cobra.Command{
	Use:   "exec --command '<cmd>' --fleet <name>",
	Short: "Execute command across fleet",
	RunE: func(cmd *cobra.Command, args []string) error {
		command, _ := cmd.Flags().GetString("command")
		fleet, _ := cmd.Flags().GetString("fleet")
		if command == "" || fleet == "" {
			return fmt.Errorf("--command and --fleet required")
		}
		fmt.Printf("Executing '%s' on fleet %s\n", command, fleet)
		// TODO: SSH to each server and run command
		c := exec.Command("echo", "[stub] would run:", command, "on", fleet)
		c.Stdout = os.Stdout
		return c.Run()
	},
}

func init() {
	fleetStatusCmd.Flags().String("fleet", "apothem", "Fleet name")
	fleetDeployCmd.Flags().String("config", "", "Fleet config YAML file")
	fleetDeployCmd.Flags().Bool("dry-run", false, "Show what would be done")
	fleetRollingUpdateCmd.Flags().String("image", "", "New Docker image tag")
	fleetRollingUpdateCmd.Flags().String("fleet", "", "Fleet name")
	fleetRollingUpdateCmd.Flags().Int("timeout", 300, "Health check timeout in seconds")
	fleetRollingUpdateCmd.Flags().StringSlice("abort-on", []string{"validators-not-legit", "header-body-desync"}, "Abort conditions")
	fleetRollingUpdateCmd.Flags().Bool("dry-run", false, "Show what would be done")
	fleetAddPeersCmd.Flags().StringSlice("peers", nil, "Peer enode URLs")
	fleetAddPeersCmd.Flags().String("fleet", "apothem", "Fleet name")
	fleetExecCmd.Flags().String("command", "", "Command to execute")
	fleetExecCmd.Flags().String("fleet", "", "Fleet name")

	fleetCmd.AddCommand(fleetStatusCmd)
	fleetCmd.AddCommand(fleetDeployCmd)
	fleetCmd.AddCommand(fleetRollingUpdateCmd)
	fleetCmd.AddCommand(fleetAddPeersCmd)
	fleetCmd.AddCommand(fleetExecCmd)
}
