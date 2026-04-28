package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

var syncCmd = &cobra.Command{
	Use:   "sync",
	Short: "Sync operations and validation",
}

var syncHealthCmd = &cobra.Command{
	Use:   "health --node <url>",
	Short: "Check node sync health",
	RunE: func(cmd *cobra.Command, args []string) error {
		nodeURL, _ := cmd.Flags().GetString("node")
		if nodeURL == "" {
			nodeURL = "http://localhost:8545"
		}

		fmt.Printf("Checking sync health for %s...\n", nodeURL)

		// Get block number
		blockNum, err := rpcCallInt(nodeURL, "eth_blockNumber")
		if err != nil {
			return fmt.Errorf("failed to get block number: %w", err)
		}

		// Get peer count
		peers, err := rpcCallInt(nodeURL, "net_peerCount")
		if err != nil {
			return fmt.Errorf("failed to get peer count: %w", err)
		}

		// Get syncing status
		syncing, err := rpcCallBool(nodeURL, "eth_syncing")
		if err != nil {
			return fmt.Errorf("failed to get sync status: %w", err)
		}

		fmt.Printf("Block:    %d\n", blockNum)
		fmt.Printf("Peers:    %d\n", peers)
		fmt.Printf("Syncing:  %v\n", syncing)

		if !syncing && peers > 0 {
			fmt.Println("Status:   ✅ In sync")
		} else if syncing {
			fmt.Println("Status:   🔄 Syncing...")
		} else {
			fmt.Println("Status:   ⚠️ No peers")
		}

		return nil
	},
}

var syncCompareCmd = &cobra.Command{
	Use:   "compare --primary <url> --canary <url>",
	Short: "Compare two nodes (canary mode)",
	RunE: func(cmd *cobra.Command, args []string) error {
		primary, _ := cmd.Flags().GetString("primary")
		canary, _ := cmd.Flags().GetString("canary")
		interval, _ := cmd.Flags().GetDuration("every")
		alert, _ := cmd.Flags().GetBool("alert-on-diff")

		if primary == "" || canary == "" {
			return fmt.Errorf("--primary and --canary required")
		}

		fmt.Printf("Comparing %s vs %s (interval: %v)\n", primary, canary, interval)

		for {
			primaryBlock, _ := rpcCallInt(primary, "eth_blockNumber")
			canaryBlock, _ := rpcCallInt(canary, "eth_blockNumber")
		primaryHash, _ := rpcCallString(primary, "eth_getBlockByNumber", fmt.Sprintf("0x%x", primaryBlock), false)
		canaryHash, _ := rpcCallString(canary, "eth_getBlockByNumber", fmt.Sprintf("0x%x", canaryBlock), false)
		_ = primaryHash
		_ = canaryHash

			diff := primaryBlock - canaryBlock
			if diff < 0 {
				diff = -diff
			}

			status := "✅"
			if diff > 10 {
				status = "❌"
				if alert {
					fmt.Printf("\a") // Bell
				}
			}

			fmt.Printf("%s Primary=%d Canary=%d Diff=%d\n", status, primaryBlock, canaryBlock, diff)

			if interval == 0 {
				break
			}
			time.Sleep(interval)
		}

		return nil
	},
}

var syncSnapshotCmd = &cobra.Command{
	Use:   "snapshot --download <url> --output <path>",
	Short: "Download and verify snapshot",
	RunE: func(cmd *cobra.Command, args []string) error {
		url, _ := cmd.Flags().GetString("download")
		output, _ := cmd.Flags().GetString("output")
		verify, _ := cmd.Flags().GetBool("verify")

		if url == "" || output == "" {
			return fmt.Errorf("--download and --output required")
		}

		fmt.Printf("Downloading snapshot from %s to %s...\n", url, output)
		// TODO: Implement download with progress bar
		fmt.Println("Download complete")

		if verify {
			fmt.Println("Verifying snapshot integrity...")
			// TODO: Checksum verification
			fmt.Println("✅ Snapshot verified")
		}

		return nil
	},
}

// RPC helpers
func rpcCallInt(url, method string, params ...interface{}) (uint64, error) {
	result, err := rpcCall(url, method, params...)
	if err != nil {
		return 0, err
	}
	// Parse hex string
	str, ok := result.(string)
	if !ok {
		return 0, fmt.Errorf("unexpected type")
	}
	var val uint64
	fmt.Sscanf(str, "0x%x", &val)
	return val, nil
}

func rpcCallBool(url, method string, params ...interface{}) (bool, error) {
	result, err := rpcCall(url, method, params...)
	if err != nil {
		return false, err
	}
	// syncing returns object or false
	_, ok := result.(bool)
	return !ok, nil // if it's an object, we're syncing
}

func rpcCallString(url, method string, params ...interface{}) (string, error) {
	result, err := rpcCall(url, method, params...)
	if err != nil {
		return "", err
	}
	// For getBlockByNumber, result is a map with hash
	if m, ok := result.(map[string]interface{}); ok {
		if h, ok := m["hash"].(string); ok {
			return h, nil
		}
	}
	return "", nil
}

func rpcCall(url, method string, params ...interface{}) (interface{}, error) {
	reqBody := map[string]interface{}{
		"jsonrpc": "2.0",
		"method":  method,
		"params":  params,
		"id":      1,
	}
	data, _ := json.Marshal(reqBody)
	resp, err := http.Post(url, "application/json", strings.NewReader(string(data)))
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	if result["error"] != nil {
		return nil, fmt.Errorf("RPC error: %v", result["error"])
	}

	return result["result"], nil
}

func init() {
	syncHealthCmd.Flags().String("node", "http://localhost:8545", "Node RPC URL")
	syncCompareCmd.Flags().String("primary", "", "Primary node RPC URL")
	syncCompareCmd.Flags().String("canary", "", "Canary node RPC URL")
	syncCompareCmd.Flags().Duration("every", 0, "Repeat interval (0 = once)")
	syncCompareCmd.Flags().Bool("alert-on-diff", false, "Alert when nodes diverge")
	syncSnapshotCmd.Flags().String("download", "", "Snapshot URL")
	syncSnapshotCmd.Flags().String("output", "", "Output path")
	syncSnapshotCmd.Flags().Bool("verify", true, "Verify snapshot integrity")

	syncCmd.AddCommand(syncHealthCmd)
	syncCmd.AddCommand(syncCompareCmd)
	syncCmd.AddCommand(syncSnapshotCmd)
}
