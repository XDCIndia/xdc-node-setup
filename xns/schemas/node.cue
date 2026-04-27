package xns

import "strings"

// ============================================================
// Enums
// ============================================================

#Network: "mainnet" | "apothem" | "devnet"
#Client:  "xdc2.6.8" | "gp5" | "erigon" | "nethermind" | "reth"
#Role:    "full" | "fullnode" | "masternode" | "rpc" | "archive"
#Runtime: "compose" | "docker" | "systemd" | "k8s"
#StateScheme: "path" | "pbss" | "hash" | "hbss"

// ============================================================
// Client Defaults
// ============================================================

_clientStateDefaults: {
	"xdc2.6.8":  "hash"
	"gp5":       "pbss"
	"erigon":    "hash"
	"nethermind": "hash"
	"reth":      "hash"
}

_clientPortDefaults: {
	"xdc2.6.8":  { http: 8545, ws: 8546, authrpc: 8551, p2p: 30303 }
	"gp5":       { http: 9645, ws: 9646, authrpc: 9651, p2p: 30322 }
	"erigon":    { http: 8547, ws: 8548, authrpc: 8551, p2p: 30305 }
	"nethermind": { http: 8548, ws: 8553, authrpc: 8551, p2p: 30304 }
	"reth":      { http: 8588, ws: 8589, authrpc: 8551, p2p: 30306 }
}

// ============================================================
// Core Node Spec
// ============================================================

#NodeSpec: {
	name:     string
	network:  #Network
	client:   #Client
	role:     #Role
	runtime:  #Runtime | *"compose"

	location: string
	serverID: string
	dataRoot: string | *"/mnt/data"

	// OPUS47: stateScheme must match client default (HARD constraint)
	// Fleet uses "pbss" for path-based, "hbss" for hash-based — these are the canonical values
	stateScheme: string & _clientStateDefaults[client]

	rpc: {
		bind:   string | *"127.0.0.1"
		port:   int | *_clientPortDefaults[client].http
		cors:   [...string] | *["*"]
		vhosts: [...string] | *["*"]
		apis:   string | *"eth,net,web3,debug,txpool,admin"

		auth: {
			required: bool | *false
			jwtPath:  string | *""
		}
	}

	ws: {
		enabled: bool | *true
		port:    int | *_clientPortDefaults[client].ws
		bind:    string | *"127.0.0.1"
		origins: [...string] | *["*"]
	}

	image: string | *""

	authrpc: {
		port: int | *_clientPortDefaults[client].authrpc
	}

	p2p: {
		port:       int | *_clientPortDefaults[client].p2p
		maxPeers:   int | *50
		noDiscover: bool | *false
		staticNodes: [...string] | *[]
		trustedNodes: [...string] | *[]
		bootnodes: [...string] | *[]
	}

	env: [string]: string

	composeService: {
		name:    string
		image:   string
		restart: string | *"unless-stopped"
		ports: [...string] | *[]
		volumes: [...string] | *[]
		environment: env
		entrypoint: [...string] | *[]
		command: string | [...string] | *""
		networkMode: string | *""
		healthcheck: {
			test: [...string] | *[]
			interval: string | *"30s"
			timeout:  string | *"10s"
			retries:  int | *5
			start_period: string | *"180s"
		} | *{}
		logging: {
			driver: string | *"json-file"
			options: [string]: string
		} | *{}
	}

	// OPUS47: 0.0.0.0 bind requires auth (exported constraint)
	opus47_rpcBind: (rpc.bind != "0.0.0.0") || (rpc.auth.required == true)

	// OPUS47: container name derived from node name (exported constraint)
	opus47_containerName: composeService.name =~ "^.*-" + name + "-.*$" || composeService.name =~ "^" + name + ".*$"

	// OPUS47: no $$ escapes in env values (exported constraint)
	opus47_envNoEscapes: true
	for k, v in env {
		let key = k
		"opus47_env_\(key)": !strings.Contains(v, "$$")
	}
}

// ============================================================
// Top-level validation — all node values must satisfy #NodeSpec
// ============================================================

node: #NodeSpec
