package xns

// ============================================================
// Example: apothem/gp5-pbss-168
// Derived from docker-compose.gp5-apothem.yml
// ============================================================

node: {
	name:     "gp5-pbss"
	network:  "apothem"
	client:   "gp5"
	role:     "full"
	runtime:  "docker"
	dataRoot: "/mnt/data"
	location: "test"
	serverID: "168"

	image: "anilchinchawale/xdc-gp5:latest"

	// PBSS node MUST use pbss state scheme (OPUS47)
	stateScheme: "pbss"

	rpc: {
		bind: "127.0.0.1"
		port: 8584
		cors: ["*"]
		vhosts: ["*"]
		apis: "admin,eth,net,web3,XDPoS"
		auth: required: false
	}

	ws: {
		enabled: true
		bind:    "127.0.0.1"
		port:    8585
		origins: ["*"]
	}

	p2p: {
		port:     30322
		maxPeers: 50
		bootnodes: [
			"enode://...",
		]
	}

	env: {
		NETWORK:       "apothem"
		NETWORK_ID:    "51"
		SYNC_MODE:     "full"
		GC_MODE:       "full"
		EXTERNAL_IP:   ""
		INSTANCE_NAME: "XDC_GP5_Apothem"
		HTTP_API:      "admin,eth,net,web3,XDPoS"
		STATS_SECRET:  "xdc_openscan_stats_2026"
	}

	composeService: {
		name:    "test-gp5-pbss-168"
		image:   "anilchinchawale/xdc-gp5:latest"
		restart: "always"
		ports: [
			"30322:30303",
			"30322:30303/udp",
			"127.0.0.1:8584:8545",
			"127.0.0.1:8585:8546",
		]
		volumes: [
			"${DATA_DIR:-../apothem}/xdcchain-gp5:/work/xdcchain",
			"./apothem/genesis.json:/work/genesis.json:ro",
			"./geth-pr5/start-gp5.sh:/work/start.sh:ro",
			"./apothem/bootnodes.list:/work/bootnodes.list:ro",
			"${DATA_DIR:-../apothem}/.xdc-node/.pwd:/work/.pwd:ro",
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
