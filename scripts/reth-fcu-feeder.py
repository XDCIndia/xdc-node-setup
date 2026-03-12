#!/usr/bin/env python3
"""
Reth FCU Feeder for XDC Pre-Merge Chains

Reth requires forkchoice updates from a beacon chain, but XDC is pre-merge PoA.
This script polls a synced XDC node and sends FCU to Reth's Engine API.

Usage:
    python3 reth-fcu-feeder.py --source http://127.0.0.1:8547 \
                                --target http://127.0.0.1:8551 \
                                --jwt-file /path/to/jwt.hex

Requirements:
    - Python 3.6+
    - No external dependencies (uses stdlib only)
"""

import argparse
import base64
import hashlib
import hmac
import json
import time
import urllib.request
import urllib.error
import sys
from typing import Optional, Dict, Any


def create_jwt(secret_hex: str) -> str:
    """
    Create a properly signed JWT token for Engine API authentication.
    
    The JWT must have:
    - Header: {"alg": "HS256", "typ": "JWT"}
    - Payload: {"iat": <current_unix_timestamp>}
    - Signature: HMAC-SHA256(header.payload, secret)
    
    Args:
        secret_hex: The JWT secret as a hex string (64 chars = 32 bytes)
    
    Returns:
        Signed JWT token string (header.payload.signature)
    """
    secret = bytes.fromhex(secret_hex.strip())
    
    # Base64url encode without padding
    def b64url(data: bytes) -> bytes:
        return base64.urlsafe_b64encode(data).rstrip(b'=')
    
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iat": int(time.time())}).encode())
    
    message = header + b'.' + payload
    signature = b64url(hmac.new(secret, message, hashlib.sha256).digest())
    
    return (message + b'.' + signature).decode()


def rpc_call(url: str, method: str, params: list, jwt_token: Optional[str] = None) -> Dict[str, Any]:
    """Make a JSON-RPC call."""
    data = json.dumps({
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": 1
    }).encode()
    
    headers = {"Content-Type": "application/json"}
    if jwt_token:
        headers["Authorization"] = f"Bearer {jwt_token}"
    
    req = urllib.request.Request(url, data=data, headers=headers)
    
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return {"error": {"code": e.code, "message": e.read().decode()}}
    except urllib.error.URLError as e:
        return {"error": {"code": -1, "message": str(e.reason)}}
    except Exception as e:
        return {"error": {"code": -1, "message": str(e)}}


def get_latest_block(source_rpc: str) -> Optional[Dict[str, Any]]:
    """Get the latest block from source node."""
    result = rpc_call(source_rpc, "eth_getBlockByNumber", ["latest", False])
    if "result" in result and result["result"]:
        return result["result"]
    return None


def send_forkchoice_update(target_auth: str, jwt_token: str, block_hash: str) -> Dict[str, Any]:
    """Send forkchoice update to Reth Engine API."""
    fcu_state = {
        "headBlockHash": block_hash,
        "safeBlockHash": block_hash,
        "finalizedBlockHash": block_hash
    }
    return rpc_call(target_auth, "engine_forkchoiceUpdatedV1", [fcu_state, None], jwt_token)


def main():
    parser = argparse.ArgumentParser(description="Reth FCU Feeder for XDC")
    parser.add_argument("--source", default="http://127.0.0.1:8547",
                        help="Source RPC URL (synced XDC node)")
    parser.add_argument("--target", default="http://127.0.0.1:8551",
                        help="Target Engine API URL (Reth authrpc)")
    parser.add_argument("--jwt-file", required=True,
                        help="Path to JWT secret hex file")
    parser.add_argument("--interval", type=int, default=2,
                        help="Polling interval in seconds")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Verbose output")
    args = parser.parse_args()
    
    # Load JWT secret
    try:
        with open(args.jwt_file) as f:
            jwt_secret = f.read().strip()
        if len(jwt_secret) != 64:
            print(f"Warning: JWT secret is {len(jwt_secret)} chars (expected 64)")
    except FileNotFoundError:
        print(f"Error: JWT file not found: {args.jwt_file}")
        sys.exit(1)
    
    print(f"Reth FCU Feeder started")
    print(f"  Source: {args.source}")
    print(f"  Target: {args.target}")
    print(f"  Interval: {args.interval}s")
    print()
    
    last_hash = None
    errors = 0
    
    while True:
        try:
            # Get latest block from source
            block = get_latest_block(args.source)
            if not block:
                if args.verbose:
                    print(f"[{time.strftime('%H:%M:%S')}] No block from source")
                time.sleep(args.interval)
                continue
            
            block_hash = block["hash"]
            block_num = block["number"]
            
            # Skip if same block
            if block_hash == last_hash:
                if args.verbose:
                    print(f"[{time.strftime('%H:%M:%S')}] Same block, skipping")
                time.sleep(args.interval)
                continue
            
            # Create fresh JWT (must be regenerated as iat expires)
            jwt_token = create_jwt(jwt_secret)
            
            # Send FCU
            result = send_forkchoice_update(args.target, jwt_token, block_hash)
            
            # Parse response
            if "result" in result and result["result"]:
                status = result["result"].get("payloadStatus", {}).get("status", "UNKNOWN")
                errors = 0
            elif "error" in result:
                status = f"ERROR: {result['error'].get('message', result['error'])}"
                errors += 1
            else:
                status = "UNKNOWN"
            
            # Log
            ts = time.strftime('%H:%M:%S')
            short_hash = block_hash[:18] + "..."
            print(f"[{ts}] Block {block_num} ({short_hash}) -> {status}")
            
            last_hash = block_hash
            
            # Backoff on repeated errors
            if errors > 5:
                print(f"Too many errors, backing off...")
                time.sleep(30)
                errors = 0
                
        except KeyboardInterrupt:
            print("\nShutting down...")
            break
        except Exception as e:
            print(f"[{time.strftime('%H:%M:%S')}] Exception: {e}")
            errors += 1
        
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
