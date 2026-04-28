package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
	"xns/pkg/render"
	"xns/pkg/spec"
)

var nodeCmd = &cobra.Command{
	Use:   "node",
	Short: "Manage a single XDC node",
}

var nodeInitCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize a new node spec file",
	RunE: func(cmd *cobra.Command, args []string) error {
		network, _ := cmd.Flags().GetString("network")
		client, _ := cmd.Flags().GetString("client")
		name, _ := cmd.Flags().GetString("name")
		datadir, _ := cmd.Flags().GetString("datadir")

		if name == "" {
			name = fmt.Sprintf("%s-%s-1", network, client)
		}
		if datadir == "" {
			datadir = filepath.Join("/data", name)
		}

		s := spec.NodeSpec{
			Name:    name,
			Network: spec.Network(network),
			Client:  spec.Client(client),
			Role:    spec.Fullnode,
			Version: "latest",
			Image:   fmt.Sprintf("xdcindia/%s:latest", client),
			Datadir: datadir,
			RPC: spec.RPCConfig{
				Enabled: true,
				Host:    "0.0.0.0",
				Port:    8545,
				APIs:    "eth,net,web3,debug,txpool",
			},
			WS: spec.RPCConfig{
				Enabled: true,
				Host:    "0.0.0.0",
				Port:    8549,
				APIs:    "eth,net,web3",
			},
			Ports:   spec.DefaultPorts(spec.Client(client)),
			Restart: "unless-stopped",
			Volumes: map[string]string{
				datadir: "/data",
			},
		}

		// Adjust ports for network
		if s.Network == spec.Apothem {
			s.Ports.RPC = 9645
			s.Ports.WS = 9649
			s.Ports.P2P = 30320
			s.RPC.Port = 9645
			s.WS.Port = 9649
		}

		outFile := fmt.Sprintf("%s.yaml", name)
		if err := writeSpecYAML(outFile, s); err != nil {
			return err
		}
		fmt.Printf("Initialized node spec: %s\n", outFile)
		fmt.Printf("  Network: %s (chainId=%d)\n", s.Network, s.Network.ChainID())
		fmt.Printf("  Client:  %s\n", s.Client)
		fmt.Printf("  Datadir: %s\n", s.Datadir)
		fmt.Printf("  Ports:   RPC=%d WS=%d P2P=%d\n", s.Ports.RPC, s.Ports.WS, s.Ports.P2P)
		fmt.Printf("\nNext: xdccli render %s | docker compose -f - up -d\n", outFile)
		return nil
	},
}

var nodeUpCmd = &cobra.Command{
	Use:   "up <spec-file>",
	Short: "Start node from spec file via docker compose",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		compose, err := renderSpecToCompose(args[0])
		if err != nil {
			return err
		}
		// Write to temp file and run docker compose
		tmpFile := "/tmp/xdc-compose-up.yml"
		if err := os.WriteFile(tmpFile, []byte(compose), 0644); err != nil {
			return err
		}
		c := exec.Command("docker", "compose", "-f", tmpFile, "up", "-d")
		c.Stdout = os.Stdout
		c.Stderr = os.Stderr
		return c.Run()
	},
}

var nodeDownCmd = &cobra.Command{
	Use:   "down <spec-file>",
	Short: "Stop node from spec file",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		compose, err := renderSpecToCompose(args[0])
		if err != nil {
			return err
		}
		tmpFile := "/tmp/xdc-compose-down.yml"
		if err := os.WriteFile(tmpFile, []byte(compose), 0644); err != nil {
			return err
		}
		c := exec.Command("docker", "compose", "-f", tmpFile, "down")
		c.Stdout = os.Stdout
		c.Stderr = os.Stderr
		return c.Run()
	},
}

var nodeStatusCmd = &cobra.Command{
	Use:   "status [container-name]",
	Short: "Show node container status",
	RunE: func(cmd *cobra.Command, args []string) error {
		name := ""
		if len(args) > 0 {
			name = args[0]
		}
		var c *exec.Cmd
		if name != "" {
			c = exec.Command("docker", "ps", "-f", "name="+name, "--format", "table {{.Names}}\t{{.Status}}\t{{.Ports}}")
		} else {
			c = exec.Command("docker", "ps", "--filter", "label=xns.managed=true", "--format", "table {{.Names}}\t{{.Status}}\t{{.Ports}}")
		}
		c.Stdout = os.Stdout
		c.Stderr = os.Stderr
		return c.Run()
	},
}

var nodeLogsCmd = &cobra.Command{
	Use:   "logs <container-name>",
	Short: "View node logs",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		follow, _ := cmd.Flags().GetBool("follow")
		tail, _ := cmd.Flags().GetString("tail")
		cmdArgs := []string{"logs"}
		if follow {
			cmdArgs = append(cmdArgs, "-f")
		}
		if tail != "" {
			cmdArgs = append(cmdArgs, "--tail", tail)
		}
		cmdArgs = append(cmdArgs, args[0])
		c := exec.Command("docker", cmdArgs...)
		c.Stdout = os.Stdout
		c.Stderr = os.Stderr
		return c.Run()
	},
}

var nodeRestoreCmd = &cobra.Command{
	Use:   "restore --snapshot <url> --datadir <path>",
	Short: "Restore node from snapshot",
	RunE: func(cmd *cobra.Command, args []string) error {
		snapshotURL, _ := cmd.Flags().GetString("snapshot")
		datadir, _ := cmd.Flags().GetString("datadir")
		if snapshotURL == "" || datadir == "" {
			return fmt.Errorf("--snapshot and --datadir required")
		}

		fmt.Printf("Downloading snapshot from %s...\n", snapshotURL)
		// Use wget or curl
		snapshotFile := "/tmp/snapshot.tar.zst"
		var c *exec.Cmd
		if _, err := exec.LookPath("wget"); err == nil {
			c = exec.Command("wget", "-c", "-q", "--show-progress", snapshotURL, "-O", snapshotFile)
		} else {
			c = exec.Command("curl", "-L", "-o", snapshotFile, snapshotURL)
		}
		c.Stdout = os.Stdout
		c.Stderr = os.Stderr
		if err := c.Run(); err != nil {
			return fmt.Errorf("download failed: %w", err)
		}

		fmt.Printf("Extracting to %s...\n", datadir)
		os.MkdirAll(datadir, 0755)
		// #1 FIX: Use unzstd as the decompressor program (tar --use-compress-program
		// takes a single program name, not 'program args').
		extract := exec.Command("tar", "--use-compress-program=unzstd", "-xf", snapshotFile, "-C", datadir)
		extract.Stdout = os.Stdout
		extract.Stderr = os.Stderr
		if err := extract.Run(); err != nil {
			return fmt.Errorf("extract failed: %w", err)
		}

		fmt.Printf("✅ Restored to %s\n", datadir)
		return nil
	},
}

func renderSpecToCompose(specFile string) (string, error) {
	s, err := readSpecYAML(specFile)
	if err != nil {
		return "", err
	}
	return render.RenderCompose(s)
}

func writeSpecYAML(path string, s spec.NodeSpec) error {
	// Simple YAML writer — in production use yaml.Marshal
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	fmt.Fprintf(f, "name: %s\n", s.Name)
	fmt.Fprintf(f, "network: %s\n", s.Network)
	fmt.Fprintf(f, "client: %s\n", s.Client)
	fmt.Fprintf(f, "role: %s\n", s.Role)
	fmt.Fprintf(f, "version: %s\n", s.Version)
	fmt.Fprintf(f, "image: %s\n", s.Image)
	fmt.Fprintf(f, "datadir: %s\n", s.Datadir)
	fmt.Fprintf(f, "ports:\n")
	fmt.Fprintf(f, "  rpc: %d\n", s.Ports.RPC)
	fmt.Fprintf(f, "  ws: %d\n", s.Ports.WS)
	fmt.Fprintf(f, "  p2p: %d\n", s.Ports.P2P)
	fmt.Fprintf(f, "rpc:\n")
	fmt.Fprintf(f, "  enabled: true\n")
	fmt.Fprintf(f, "  host: %s\n", s.RPC.Host)
	fmt.Fprintf(f, "  port: %d\n", s.RPC.Port)
	fmt.Fprintf(f, "  apis: %s\n", s.RPC.APIs)
	fmt.Fprintf(f, "ws:\n")
	fmt.Fprintf(f, "  enabled: true\n")
	fmt.Fprintf(f, "  host: %s\n", s.WS.Host)
	fmt.Fprintf(f, "  port: %d\n", s.WS.Port)
	fmt.Fprintf(f, "  apis: %s\n", s.WS.APIs)
	fmt.Fprintf(f, "volumes:\n")
	for k, v := range s.Volumes {
		fmt.Fprintf(f, "  %s: %s\n", k, v)
	}
	fmt.Fprintf(f, "restart: %s\n", s.Restart)
	return nil
}

func readSpecYAML(path string) (*spec.NodeSpec, error) {
	// #2 FIX: Real YAML unmarshalling via gopkg.in/yaml.v3
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read spec: %w", err)
	}
	var s spec.NodeSpec
	if err := yaml.Unmarshal(data, &s); err != nil {
		return nil, fmt.Errorf("parse spec: %w", err)
	}
	return &s, nil
}

func init() {
	nodeInitCmd.Flags().String("network", "apothem", "Network: mainnet, apothem, devnet")
	nodeInitCmd.Flags().String("client", "gp5", "Client: gp5, xdc268, erigon, nethermind, reth")
	nodeInitCmd.Flags().String("name", "", "Node name (auto-generated if empty)")
	nodeInitCmd.Flags().String("datadir", "", "Data directory (auto-generated if empty)")

	nodeLogsCmd.Flags().BoolP("follow", "f", false, "Follow log output")
	nodeLogsCmd.Flags().String("tail", "100", "Number of lines to show from end")

	nodeRestoreCmd.Flags().String("snapshot", "", "Snapshot URL to download")
	nodeRestoreCmd.Flags().String("datadir", "", "Target data directory")

	nodeCmd.AddCommand(nodeInitCmd)
	nodeCmd.AddCommand(nodeUpCmd)
	nodeCmd.AddCommand(nodeDownCmd)
	nodeCmd.AddCommand(nodeStatusCmd)
	nodeCmd.AddCommand(nodeLogsCmd)
	nodeCmd.AddCommand(nodeRestoreCmd)
}
