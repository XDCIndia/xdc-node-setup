package spec

import (
	"testing"
)

func TestNodeSpecValidate(t *testing.T) {
	valid := &NodeSpec{
		Name:    "test",
		Network: Mainnet,
		Client:  XDC268,
		Role:    Fullnode,
		Image:   "xdc:latest",
		Datadir: "/data",
	}
	if err := valid.Validate(); err != nil {
		t.Fatalf("expected valid spec: %v", err)
	}

	invalid := &NodeSpec{}
	if err := invalid.Validate(); err == nil {
		t.Fatal("expected validation error for empty spec")
	}
}

func TestNetworkChainID(t *testing.T) {
	if Mainnet.ChainID() != 50 {
		t.Errorf("mainnet chainid want 50 got %d", Mainnet.ChainID())
	}
	if Apothem.ChainID() != 51 {
		t.Errorf("apothem chainid want 51 got %d", Apothem.ChainID())
	}
	if Devnet.ChainID() != 551 {
		t.Errorf("devnet chainid want 551 got %d", Devnet.ChainID())
	}
}

func TestClientFlagPrefixes(t *testing.T) {
	if XDC268.RPCFlagPrefix() != "rpc" {
		t.Errorf("xdc268 rpc prefix want rpc got %s", XDC268.RPCFlagPrefix())
	}
	if GP5.RPCFlagPrefix() != "http" {
		t.Errorf("gp5 rpc prefix want http got %s", GP5.RPCFlagPrefix())
	}
	if Nethermind.RPCFlagPrefix() != "JsonRpc" {
		t.Errorf("nethermind rpc prefix want JsonRpc got %s", Nethermind.RPCFlagPrefix())
	}
}

func TestDefaultPorts(t *testing.T) {
	p := DefaultPorts(Erigon)
	if p.RPC != 8547 || p.WS != 8548 || p.P2P != 30305 {
		t.Errorf("erigon ports mismatch: %+v", p)
	}
}
