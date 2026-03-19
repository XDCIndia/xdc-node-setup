#!/usr/bin/env python3
"""
XDC Reth FCU Feeder Script

Sends ForkChoiceUpdated (FCU) messages to Reth to trigger backfill sync.
Required because Reth cannot directly handshake with XDC geth peers (ECIES issue).

Uses Erigon as the source of truth for block hashes until ECIES is fixed.
"""

import requests
import time
import os
import sys
from typing import Optional

# Configuration
RETH_RPC = os.getenv("RETH_RPC", "http://localhost:8548")
SOURCE_RPC = os.getenv("SOURCE_RPC", "http://localhost:8546")  # Erigon
NETWORK = os.getenv("NETWORK", "mainnet")

# Genesis hashes
GENESIS_HASHES = {
    "mainnet": "0x4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1",
    "apothem": "0xbdea512b4f12ff1135ec92c00dc047ffb93890c2ea1aa0eefe9b013d80640075"
}

class FCUFeeder:
    def __init__(self, reth_rpc: str, source_rpc: str, network: str):
        self.reth_rpc = reth_rpc
        self.source_rpc = source_rpc
        self.network = network
        self.genesis_hash = GENESIS_HASHES.get(network, GENESIS_HASHES["mainnet"])
        self.last_head = None
        
    def get_head_block(self) -> Optional[str]:
        """Get current head block hash from source (Erigon)"""
        try:
            resp = requests.post(
                self.source_rpc,
                json={
                    "jsonrpc": "2.0",
                    "method": "eth_blockNumber",
                    "params": [],
                    "id": 1
                },
                timeout=10
            )
            resp.raise_for_status()
            block_num = resp.json().get("result")
            
            if not block_num:
                return None
                
            # Get block hash
            resp = requests.post(
                self.source_rpc,
                json={
                    "jsonrpc": "2.0",
                    "method": "eth_getBlockByNumber",
                    "params": [block_num, False],
                    "id": 2
                },
                timeout=10
            )
            resp.raise_for_status()
            block = resp.json().get("result")
            return block.get("hash") if block else None
            
        except Exception as e:
            print(f"Error getting head block: {e}")
            return None
    
    def send_fcu(self, head_hash: str, finalized_hash: str) -> bool:
        """Send ForkChoiceUpdated to Reth"""
        try:
            resp = requests.post(
                self.reth_rpc,
                json={
                    "jsonrpc": "2.0",
                    "method": "engine_forkchoiceUpdatedV1",
                    "params": [
                        {
                            "headBlockHash": head_hash,
                            "safeBlockHash": head_hash,
                            "finalizedBlockHash": finalized_hash
                        },
                        None  # No payload attributes
                    ],
                    "id": 3
                },
                timeout=10
            )
            resp.raise_for_status()
            result = resp.json()
            
            if "error" in result:
                print(f"FCU error: {result['error']}")
                return False
                
            return True
            
        except Exception as e:
            print(f"Error sending FCU: {e}")
            return False
    
    def run(self):
        """Main loop - send FCU every 30 seconds"""
        print(f"XDC Reth FCU Feeder starting...")
        print(f"Network: {self.network}")
        print(f"Reth RPC: {self.reth_rpc}")
        print(f"Source RPC: {self.source_rpc}")
        print(f"Genesis: {self.genesis_hash}")
        print("")
        
        while True:
            try:
                head = self.get_head_block()
                
                if head:
                    if head != self.last_head:
                        print(f"New head: {head}")
                        
                    # Send FCU with genesis as finalized (triggers backfill)
                    if self.send_fcu(head, self.genesis_hash):
                        print(f"FCU sent: head={head[:20]}...")
                        self.last_head = head
                    else:
                        print("FCU failed, will retry...")
                else:
                    print("Could not get head block, retrying...")
                    
            except KeyboardInterrupt:
                print("\nShutting down...")
                sys.exit(0)
            except Exception as e:
                print(f"Unexpected error: {e}")
            
            time.sleep(30)


def main():
    feeder = FCUFeeder(RETH_RPC, SOURCE_RPC, NETWORK)
    feeder.run()


if __name__ == "__main__":
    main()
