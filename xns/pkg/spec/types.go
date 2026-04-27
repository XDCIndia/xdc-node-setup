package spec

import (
	"fmt"
	"strings"
)

// Network identifies the XDC network.
type Network string

const (
	Mainnet Network = "mainnet"
	Apothem Network = "apothem"
	Devnet  Network = "devnet"
)

// Client identifies the execution client.
type Client string

const (
	XDC268    Client = "xdc268"
	GP5       Client = "gp5"
	Erigon    Client = "erigon"
	Nethermind Client = "nethermind"
	Reth      Client = "reth"
)

// Role identifies the node role.
type Role string

const (
	Fullnode   Role = "fullnode"
	Masternode Role = "masternode"
	RPC        Role = "rpc"
	Archive    Role = "archive"
)

// ChainID returns the chain ID for a network.
func (n Network) ChainID() int {
	switch n {
	case Mainnet:
		return 50
	case Apothem:
		return 51
	case Devnet:
		return 551
	default:
		return 0
	}
}

// RPCConfig holds RPC/WS listener settings.
type RPCConfig struct {
	Enabled bool   `yaml:"enabled" json:"enabled"`
	Host    string `yaml:"host" json:"host"`
	Port    int    `yaml:"port" json:"port"`
	VHosts  string `yaml:"vhosts,omitempty" json:"vhosts,omitempty"`
	CORS    string `yaml:"cors,omitempty" json:"cors,omitempty"`
	APIs    string `yaml:"apis,omitempty" json:"apis,omitempty"`
}

// PortConfig holds all port mappings.
type PortConfig struct {
	RPC  int `yaml:"rpc" json:"rpc"`
	WS   int `yaml:"ws" json:"ws"`
	P2P  int `yaml:"p2p" json:"p2p"`
	Auth int `yaml:"auth,omitempty" json:"auth,omitempty"`
}

// PeerConfig holds peering settings.
type PeerConfig struct {
	MaxPeers     int      `yaml:"maxPeers,omitempty" json:"maxPeers,omitempty"`
	StaticNodes  []string `yaml:"staticNodes,omitempty" json:"staticNodes,omitempty"`
	Bootnodes    []string `yaml:"bootnodes,omitempty" json:"bootnodes,omitempty"`
	TrustedNodes []string `yaml:"trustedNodes,omitempty" json:"trustedNodes,omitempty"`
}

// NodeSpec is the top-level node specification.
type NodeSpec struct {
	Name        string            `yaml:"name" json:"name"`
	Network     Network           `yaml:"network" json:"network"`
	Client      Client            `yaml:"client" json:"client"`
	Role        Role              `yaml:"role" json:"role"`
	Version     string            `yaml:"version" json:"version"`
	Image       string            `yaml:"image" json:"image"`
	Datadir     string            `yaml:"datadir" json:"datadir"`
	RPC         RPCConfig         `yaml:"rpc" json:"rpc"`
	WS          RPCConfig         `yaml:"ws" json:"ws"`
	Ports       PortConfig        `yaml:"ports" json:"ports"`
	Peers       PeerConfig        `yaml:"peers,omitempty" json:"peers,omitempty"`
	Flags       []string          `yaml:"flags,omitempty" json:"flags,omitempty"`
	Env         map[string]string `yaml:"env,omitempty" json:"env,omitempty"`
	Volumes     map[string]string `yaml:"volumes,omitempty" json:"volumes,omitempty"`
	Restart     string            `yaml:"restart,omitempty" json:"restart,omitempty"`
	ExtraHosts  []string          `yaml:"extraHosts,omitempty" json:"extraHosts,omitempty"`
}

// Validate checks the spec for errors.
func (s *NodeSpec) Validate() error {
	var errs []string

	if s.Name == "" {
		errs = append(errs, "name is required")
	}

	switch s.Network {
	case Mainnet, Apothem, Devnet:
	default:
		errs = append(errs, fmt.Sprintf("invalid network: %q", s.Network))
	}

	switch s.Client {
	case XDC268, GP5, Erigon, Nethermind, Reth:
	default:
		errs = append(errs, fmt.Sprintf("invalid client: %q", s.Client))
	}

	switch s.Role {
	case Fullnode, Masternode, RPC, Archive:
	default:
		errs = append(errs, fmt.Sprintf("invalid role: %q", s.Role))
	}

	if s.Image == "" {
		errs = append(errs, "image is required")
	}

	if s.Datadir == "" {
		errs = append(errs, "datadir is required")
	}

	if len(errs) > 0 {
		return fmt.Errorf("validation failed: %s", strings.Join(errs, "; "))
	}

	return nil
}

// IsMasternode returns true if the node is a masternode.
func (s *NodeSpec) IsMasternode() bool {
	return s.Role == Masternode
}

// DefaultPorts returns default ports for a client.
func DefaultPorts(client Client) PortConfig {
	switch client {
	case XDC268, GP5:
		return PortConfig{RPC: 8545, WS: 8549, P2P: 30303, Auth: 8551}
	case Erigon:
		return PortConfig{RPC: 8547, WS: 8548, P2P: 30305, Auth: 8551}
	case Nethermind:
		return PortConfig{RPC: 8548, WS: 8553, P2P: 30304, Auth: 8551}
	case Reth:
		return PortConfig{RPC: 8588, WS: 0, P2P: 30306, Auth: 8551}
	default:
		return PortConfig{RPC: 8545, WS: 8546, P2P: 30303, Auth: 8551}
	}
}

// RPCFlagPrefix returns the CLI prefix for RPC flags for this client.
func (c Client) RPCFlagPrefix() string {
	switch c {
	case XDC268:
		return "rpc"
	case GP5:
		return "http"
	case Erigon:
		return "http"
	case Nethermind:
		return "JsonRpc"
	case Reth:
		return "http"
	default:
		return "rpc"
	}
}

// WSFlagPrefix returns the CLI prefix for WS flags for this client.
func (c Client) WSFlagPrefix() string {
	switch c {
	case XDC268:
		return "ws"
	case GP5:
		return "ws"
	case Erigon:
		return "ws"
	case Nethermind:
		return "JsonRpc.Ws"
	case Reth:
		return "ws"
	default:
		return "ws"
	}
}
