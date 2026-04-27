package xns

// ============================================================
// Example: mainnet/gp5-pbss-125
// Derived from docker-compose.gp5-standalone.yml (mainnet variant)
// ============================================================

node: {
	name:     "gp5-pbss"
	network:  "mainnet"
	client:   "gp5"
	role:     "full"
	runtime:  "docker"
	dataRoot: "/mnt/data"
	location: "prod"
	serverID: "125"

	image: "anilchinchawale/xdc-gp5:latest"

	// PBSS node MUST use pbss state scheme (OPUS47)
	stateScheme: "pbss"

	rpc: {
		bind: "127.0.0.1"
		port: 8582
		cors: ["*"]
		vhosts: ["*"]
		apis: "admin,eth,net,web3,XDPoS"
		auth: required: false
	}

	ws: {
		enabled: true
		bind:    "127.0.0.1"
		port:    8583
		origins: ["*"]
	}

	p2p: {
		port:     30303
		maxPeers: 50
		bootnodes: [
			"enode://...",
		]
	}

	env: {
		NETWORK:       "mainnet"
		NETWORK_ID:    "50"
		SYNC_MODE:     "full"
		GC_MODE:       "full"
		EXTERNAL_IP:   ""
		INSTANCE_NAME: "XDC_GP5"
		HTTP_API:      "admin,eth,net,web3,XDPoS"
		STATS_SECRET:  "xdc_openscan_stats_2026"
	}

	composeService: {
		name:    "prod-gp5-pbss-125"
		image:   "anilchinchawale/xdc-gp5:latest"
		restart: "always"
		ports: [
			"30303:30303",
			"30303:30303/udp",
			"127.0.0.1:8582:8545",
			"127.0.0.1:8583:8546",
		]
		volumes: [
			"${DATA_DIR:-../mainnet}/xdcchain-gp5:/work/xdcchain",
			"./mainnet/genesis.json:/work/genesis.json:ro",
			"./geth-pr5/start-gp5.sh:/work/start.sh:ro",
			"./mainnet/bootnodes.list:/work/bootnodes.list:ro",
			"${DATA_DIR:-../mainnet}/.xdc-node/.pwd:/work/.pwd:ro",
			"/etc/localtime:/etc/localtime:ro",
		]
		environment: env
		entrypoint: ["/bin/sh", "/work/start.sh"]
		healthcheck: {
			test: ["CMD-SHELL", "wget -qO- http://localhost:8545 --post-data='{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' --header='Content-Type: application/json' | grep -q 'result' || exit 1"]
			interval:    "30s"
			timeout:     "10s"
			retries:     5
			start_period: "180s"
		}
		logging: {
			driver: "json-file"
			options: {
				"max-size": "100m"
				"max-file": "5"
			}
		}
	}
}
