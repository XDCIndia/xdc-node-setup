#!/usr/bin/env python3
"""
XDC Reth FCU Feeder - Bridges XDPoS consensus to Reth's Engine API.
Spec: https://github.com/AnilChinchawale/xdc-node-setup/blob/main/docs/FCU-ENGINE-API.md

Usage:
  NETWORK=mainnet python3 fcu-feeder.py
  NETWORK=apothem python3 fcu-feeder.py

  Or override individually:
  SOURCE=http://127.0.0.1:8546 TARGET=http://127.0.0.1:8551 JWT_SECRET=<hex> python3 fcu-feeder.py
"""
import base64, hashlib, hmac, json, os, time, urllib.request

# Network configs (source = Erigon RPC)
NETWORKS = {
    "mainnet": {
        "genesis":  "0x4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1",
        "source":   "http://127.0.0.1:8546",   # Erigon RPC (mainnet)
        "target":   "http://127.0.0.1:8551",   # Reth authrpc
        "jwt_file": "/root/reth-mainnet-data/jwt.hex",
    },
    "apothem": {
        "genesis":  "0xbdea512b4f12ff1135ec92c00dc047ffb93890c2ea1aa0eefe9b013d80640075",
        "source":   "http://127.0.0.1:8547",   # Erigon RPC (apothem, default port)
        "target":   "http://127.0.0.1:8552",   # Reth authrpc (apothem)
        "jwt_file": "/root/reth-apothem-data/jwt.hex",
    },
}

def create_jwt(secret_hex):
    """Generate HS256 JWT token for Engine API authentication."""
    clean = secret_hex.strip()
    if clean.startswith("0x") or clean.startswith("0X"):
        clean = clean[2:]
    secret = bytes.fromhex(clean)
    def b64url(data):
        return base64.urlsafe_b64encode(data).rstrip(b"=")
    header  = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iat": int(time.time())}).encode())
    message = header + b"." + payload
    sig     = b64url(hmac.new(secret, message, hashlib.sha256).digest())
    return (message + b"." + sig).decode()

def rpc_call(url, method, params, jwt_token=None):
    """Send JSON-RPC request with optional JWT auth."""
    data    = json.dumps({"jsonrpc": "2.0", "method": method, "params": params, "id": 1}).encode()
    headers = {"Content-Type": "application/json"}
    if jwt_token:
        headers["Authorization"] = f"Bearer {jwt_token}"
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": {"message": str(e)}}

def load_jwt(config):
    """Load JWT secret: env var → file."""
    # Env var takes priority (for Docker deployments)
    secret = os.environ.get("JWT_SECRET", "").strip()
    if secret:
        return secret
    # Fall back to file
    jwt_file = os.environ.get("JWT_FILE", config.get("jwt_file", ""))
    if jwt_file and os.path.exists(jwt_file):
        return open(jwt_file).read().strip()
    raise RuntimeError(f"No JWT secret found. Set JWT_SECRET env var or provide {jwt_file}")

def main():
    network = os.environ.get("NETWORK", "mainnet")
    config  = NETWORKS.get(network, NETWORKS["mainnet"])

    # Allow full override via env vars
    source  = os.environ.get("SOURCE",  os.environ.get("ERIGON_RPC", config["source"]))
    target  = os.environ.get("TARGET",  os.environ.get("RETH_ENGINE", config["target"]))
    genesis = os.environ.get("GENESIS_HASH", config["genesis"])

    jwt_secret = load_jwt(config)
    interval   = int(os.environ.get("FCU_INTERVAL", "30"))

    print(f"[FCU] XDC Reth FCU Feeder — {network.upper()}", flush=True)
    print(f"[FCU] Source (Erigon): {source}", flush=True)
    print(f"[FCU] Target (Reth):   {target}", flush=True)
    print(f"[FCU] Genesis:         {genesis[:20]}...", flush=True)
    print(f"[FCU] Interval:        {interval}s (skips duplicate blocks)", flush=True)

    last_hash = None
    errors    = 0

    while True:
        try:
            # 1. Get latest block from Erigon
            result = rpc_call(source, "eth_getBlockByNumber", ["latest", False])
            block  = result.get("result")
            if not block:
                msg = result.get("error", {}).get("message", "no result")
                print(f"[FCU] WARN source offline: {msg}", flush=True)
                errors += 1
                time.sleep(min(5 * (2 ** min(errors, 4)), 60))
                continue

            block_hash = block["hash"]
            block_num  = int(block["number"], 16)

            # 2. Skip if same block (no new blocks from Erigon yet)
            if block_hash == last_hash:
                time.sleep(interval)
                continue

            # 3. Fresh JWT per request (iat must be current)
            jwt_token = create_jwt(jwt_secret)

            # 4. Send FCU — finalizedBlockHash ALWAYS genesis
            fcu_state = {
                "headBlockHash":      block_hash,
                "safeBlockHash":      block_hash,
                "finalizedBlockHash": genesis,
            }
            result = rpc_call(target, "engine_forkchoiceUpdatedV1", [fcu_state, None], jwt_token)

            if "result" in result:
                status = result["result"].get("payloadStatus", {}).get("status", "?")
            else:
                status = f"ERR: {result.get('error', {}).get('message', '?')}"

            print(f"[FCU] erigon={block_num:,} hash={block_hash[:16]} status={status}", flush=True)
            last_hash = block_hash
            errors    = 0

        except KeyboardInterrupt:
            print("\n[FCU] Stopped.", flush=True)
            break
        except Exception as e:
            errors += 1
            print(f"[FCU] ERROR ({errors}): {e}", flush=True)

        # Exponential backoff on repeated errors
        sleep_time = min(30 * (2 ** min(errors - 1, 4)), 480) if errors > 0 else interval
        time.sleep(sleep_time)

if __name__ == "__main__":
    main()
