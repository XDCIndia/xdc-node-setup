
package test

#Role: "full" | "fullnode" | "masternode" | "rpc" | "archive"

_clientStateDefaults: {
    "gp5": "path"
    "erigon": "path"
    "xdc2.6.8": "hash"
}

#NodeSpec: {
    role: #Role
    client: string
    stateScheme: string & _clientStateDefaults[client]
}

// Top-level constraint
node: #NodeSpec

// Instance with conflicting value
node: {
    role: "fullnode"
    client: "gp5"
    stateScheme: "hash"
}
