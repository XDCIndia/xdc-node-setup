package render

import (
	"strings"
	"testing"

	"xns/pkg/spec"
)

func TestRenderCompose(t *testing.T) {
	s := &spec.NodeSpec{
		Name:    "test",
		Network: spec.Apothem,
		Client:  spec.GP5,
		Role:    spec.Fullnode,
		Image:   "xdcfoundation/xdcgp5:latest",
		Datadir: "/var/xdc/test",
		RPC: spec.RPCConfig{
			Enabled: true,
			Host:    "0.0.0.0",
			Port:    8545,
			APIs:    "eth,net",
		},
		WS: spec.RPCConfig{
			Enabled: true,
			Host:    "0.0.0.0",
			Port:    8549,
		},
		Ports: spec.PortConfig{RPC: 8545, WS: 8549, P2P: 30303},
		Peers: spec.PeerConfig{MaxPeers: 25},
	}

	out, err := RenderCompose(s)
	if err != nil {
		t.Fatalf("render: %v", err)
	}

	if !strings.Contains(out, "services:") {
		t.Error("missing services header")
	}
	if !strings.Contains(out, "xdcfoundation/xdcgp5:latest") {
		t.Error("missing image")
	}
	if !strings.Contains(out, "--http") {
		t.Error("missing --http flag for gp5")
	}
	if !strings.Contains(out, "--networkid") {
		t.Error("missing --networkid")
	}
}

func TestRenderComposeMasternode(t *testing.T) {
	s := &spec.NodeSpec{
		Name:    "mn",
		Network: spec.Mainnet,
		Client:  spec.XDC268,
		Role:    spec.Masternode,
		Image:   "xdc:v2.6.8",
		Datadir: "/data",
		RPC:     spec.RPCConfig{Enabled: true, Host: "0.0.0.0", Port: 8545},
		Ports:   spec.PortConfig{RPC: 8545, P2P: 30303},
	}

	out, err := RenderCompose(s)
	if err != nil {
		t.Fatalf("render: %v", err)
	}

	if !strings.Contains(out, "--mine") {
		t.Error("missing --mine for masternode")
	}
	if !strings.Contains(out, "--masternode") {
		t.Error("missing --masternode for masternode")
	}
	if !strings.Contains(out, "--rpc") {
		t.Error("missing --rpc for xdc268")
	}
}
