#!/usr/bin/env python3
"""
Reth FCU Feeder for XDC Pre-Merge Chains

Reth requires forkchoice updates from a beacon chain, but XDC is pre-merge PoA.
This script polls a synced XDC node and sends FCU to Reth's Engine API.

Supported Networks:
    - XDC Mainnet (network_id: 50)
    - XDC Apothem Testnet (network_id: 51)

Usage:
    python3 reth-fcu-feeder.py --source http://127.0.0.1:8547 \
                                --target http://127.0.0.1:8551 \
                                --jwt-file /path/to/jwt.hex \
                                --network mainnet

Requirements:
    - Python 3.7+
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
import os
import signal
import logging
from typing import Optional, Dict, Any, Tuple
from dataclasses import dataclass
from enum import IntEnum

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('reth-fcu-feeder')


class NetworkType(IntEnum):
    """XDC Network types"""
    MAINNET = 50
    APOTHEM = 51
    DEVNET = 551  # For local development

    @classmethod
    def from_string(cls, s: str) -> 'NetworkType':
        """Parse network type from string"""
        mapping = {
            'mainnet': cls.MAINNET,
            'apothem': cls.APOTHEM,
            'devnet': cls.DEVNET,
            '50': cls.MAINNET,
            '51': cls.APOTHEM,
            '551': cls.DEVNET,
        }
        try:
            return mapping[s.lower().strip()]
        except KeyError:
            raise ValueError(f"Unknown network: {s}. Use: mainnet, apothem, or devnet")


@dataclass
class NetworkConfig:
    """Configuration for a specific XDC network"""
    name: str
    network_id: int
    chain_id: int
    default_source_rpc: str
    default_target_authrpc: str
    block_time_seconds: int = 2  # XDC has ~2s block time
    
    # FCU-specific settings
    safe_block_offset: int = 10  # safe = head - 10
    finalized_block_offset: int = 20  # finalized = head - 20


# Network configurations
NETWORK_CONFIGS = {
    NetworkType.MAINNET: NetworkConfig(
        name="XDC Mainnet",
        network_id=50,
        chain_id=50,
        default_source_rpc="http://127.0.0.1:8547",
        default_target_authrpc="http://127.0.0.1:8551",
        block_time_seconds=2,
        safe_block_offset=10,
        finalized_block_offset=20,
    ),
    NetworkType.APOTHEM: NetworkConfig(
        name="XDC Apothem Testnet",
        network_id=51,
        chain_id=51,
        default_source_rpc="http://127.0.0.1:8548",
        default_target_authrpc="http://127.0.0.1:8552",
        block_time_seconds=2,
        safe_block_offset=5,
        finalized_block_offset=10,
    ),
    NetworkType.DEVNET: NetworkConfig(
        name="XDC Devnet",
        network_id=551,
        chain_id=551,
        default_source_rpc="http://127.0.0.1:8545",
        default_target_authrpc="http://127.0.0.1:8551",
        block_time_seconds=2,
        safe_block_offset=3,
        finalized_block_offset=5,
    ),
}


class FCUFeederError(Exception):
    """Base exception for FCU feeder errors"""
    pass


class JWTError(FCUFeederError):
    """JWT authentication errors"""
    pass


class RPCError(FCUFeederError):
    """RPC communication errors"""
    pass


class NetworkError(FCUFeederError):
    """Network-related errors"""
    pass


def create_jwt(secret_hex: str) -> str:
    """
    Create a properly signed JWT token for Engine API authentication.
    
    The JWT must have:
    - Header: {"alg": "HS256", "typ": "JWT"}
    - Payload: {"iat": <current_unix_timestamp>, "exp": <expiry>}
    - Signature: HMAC-SHA256(header.payload, secret)
    
    Args:
        secret_hex: The JWT secret as a hex string (64 chars = 32 bytes)
    
    Returns:
        Signed JWT token string (header.payload.signature)
    
    Raises:
        JWTError: If the secret is invalid
    """
    try:
        secret = bytes.fromhex(secret_hex.strip())
        if len(secret) != 32:
            raise JWTError(f"JWT secret must be 32 bytes (64 hex chars), got {len(secret)} bytes")
    except ValueError as e:
        raise JWTError(f"Invalid JWT secret format: {e}")
    
    # Base64url encode without padding
    def b64url(data: bytes) -> bytes:
        return base64.urlsafe_b64encode(data).rstrip(b'=')
    
    now = int(time.time())
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = b64url(json.dumps({
        "iat": now,
        "exp": now + 60  # 60 second expiry
    }).encode())
    
    message = header + b'.' + payload
    signature = b64url(hmac.new(secret, message, hashlib.sha256).digest())
    
    return (message + b'.' + signature).decode()


def rpc_call(
    url: str, 
    method: str, 
    params: list, 
    jwt_token: Optional[str] = None,
    timeout_seconds: int = 10
) -> Dict[str, Any]:
    """
    Make a JSON-RPC call.
    
    Args:
        url: RPC endpoint URL
        method: JSON-RPC method name
        params: Method parameters
        jwt_token: Optional JWT token for authentication
        timeout_seconds: Request timeout
    
    Returns:
        JSON-RPC response dictionary
    
    Raises:
        RPCError: If the RPC call fails
        NetworkError: If there's a network connectivity issue
    """
    data = json.dumps({
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": int(time.time() * 1000) % 1000000  # Unique-ish ID
    }).encode('utf-8')
    
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    
    if jwt_token:
        headers["Authorization"] = f"Bearer {jwt_token}"
    
    req = urllib.request.Request(
        url, 
        data=data, 
        headers=headers,
        method='POST'
    )
    
    try:
        with urllib.request.urlopen(req, timeout=timeout_seconds) as resp:
            response_data = resp.read().decode('utf-8')
            try:
                return json.loads(response_data)
            except json.JSONDecodeError as e:
                raise RPCError(f"Invalid JSON response: {e}. Data: {response_data[:200]}")
                
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8', errors='replace')[:500]
        raise RPCError(f"HTTP {e.code}: {error_body}")
        
    except urllib.error.URLError as e:
        raise NetworkError(f"Connection failed to {url}: {e.reason}")
        
    except TimeoutError:
        raise NetworkError(f"Request to {url} timed out after {timeout_seconds}s")
        
    except Exception as e:
        raise RPCError(f"Unexpected error: {type(e).__name__}: {e}")


def get_latest_block(source_rpc: str, timeout: int = 10) -> Optional[Dict[str, Any]]:
    """
    Get the latest block from source node.
    
    Args:
        source_rpc: Source RPC URL
        timeout: Request timeout
    
    Returns:
        Block data dictionary or None if unavailable
    """
    try:
        result = rpc_call(source_rpc, "eth_getBlockByNumber", ["latest", False], timeout_seconds=timeout)
        if "result" in result and result["result"]:
            return result["result"]
        elif "error" in result:
            logger.error(f"Source RPC error: {result['error']}")
            return None
        else:
            logger.warning("Source returned empty result")
            return None
    except (RPCError, NetworkError) as e:
        logger.error(f"Failed to get latest block: {e}")
        return None


def get_block_by_number(
    source_rpc: str, 
    block_number: int,
    timeout: int = 10
) -> Optional[Dict[str, Any]]:
    """
    Get a specific block by number.
    
    Args:
        source_rpc: Source RPC URL
        block_number: Block number to fetch
        timeout: Request timeout
    
    Returns:
        Block data dictionary or None if unavailable
    """
    hex_number = hex(block_number)
    try:
        result = rpc_call(source_rpc, "eth_getBlockByNumber", [hex_number, False], timeout_seconds=timeout)
        if "result" in result and result["result"]:
            return result["result"]
        return None
    except (RPCError, NetworkError) as e:
        logger.error(f"Failed to get block {block_number}: {e}")
        return None


def send_forkchoice_update(
    target_auth: str, 
    jwt_token: str, 
    head_hash: str,
    safe_hash: str,
    finalized_hash: str,
    timeout: int = 10
) -> Tuple[bool, str, Optional[Dict]]:
    """
    Send forkchoice update to Reth Engine API.
    
    Args:
        target_auth: Engine API URL
        jwt_token: JWT authentication token
        head_hash: Head block hash
        safe_hash: Safe block hash
        finalized_hash: Finalized block hash
        timeout: Request timeout
    
    Returns:
        Tuple of (success, status_message, full_result)
    """
    fcu_state = {
        "headBlockHash": head_hash,
        "safeBlockHash": safe_hash,
        "finalizedBlockHash": finalized_hash
    }
    
    try:
        result = rpc_call(
            target_auth, 
            "engine_forkchoiceUpdatedV1", 
            [fcu_state, None], 
            jwt_token,
            timeout_seconds=timeout
        )
        
        if "result" in result and result["result"]:
            payload_status = result["result"].get("payloadStatus", {})
            status = payload_status.get("status", "UNKNOWN")
            
            # Check for validation errors
            if status == "INVALID":
                validation_error = payload_status.get("validationError", "Unknown error")
                return False, f"INVALID: {validation_error}", result
            elif status == "SYNCING":
                return True, "SYNCING", result
            elif status == "VALID":
                return True, "VALID", result
            else:
                return True, status, result
                
        elif "error" in result:
            error_msg = result["error"].get("message", str(result["error"]))
            error_code = result["error"].get("code", "unknown")
            return False, f"ERROR {error_code}: {error_msg}", result
        else:
            return False, "UNKNOWN: Empty response", result
            
    except (RPCError, NetworkError) as e:
        return False, f"REQUEST_FAILED: {e}", None


def calculate_safe_finalized_hashes(
    source_rpc: str,
    head_number: int,
    head_hash: str,
    config: NetworkConfig
) -> Tuple[str, str]:
    """
    Calculate safe and finalized block hashes based on head.
    
    For XDC, we calculate:
    - safe = head - safe_block_offset (or head if not enough history)
    - finalized = head - finalized_block_offset (or head if not enough history)
    
    Args:
        source_rpc: Source RPC URL
        head_number: Current head block number
        head_hash: Current head block hash
        config: Network configuration
    
    Returns:
        Tuple of (safe_hash, finalized_hash)
    """
    safe_number = max(0, head_number - config.safe_block_offset)
    finalized_number = max(0, head_number - config.finalized_block_offset)
    
    # Default to head hash if we can't fetch
    safe_hash = head_hash
    finalized_hash = head_hash
    
    # Try to fetch safe block
    if safe_number < head_number:
        safe_block = get_block_by_number(source_rpc, safe_number, timeout=5)
        if safe_block and "hash" in safe_block:
            safe_hash = safe_block["hash"]
            logger.debug(f"Safe block: #{safe_number} ({safe_hash[:16]}...)")
        else:
            logger.warning(f"Could not fetch safe block #{safe_number}, using head")
    
    # Try to fetch finalized block
    if finalized_number < head_number:
        finalized_block = get_block_by_number(source_rpc, finalized_number, timeout=5)
        if finalized_block and "hash" in finalized_block:
            finalized_hash = finalized_block["hash"]
            logger.debug(f"Finalized block: #{finalized_number} ({finalized_hash[:16]}...)")
        else:
            logger.warning(f"Could not fetch finalized block #{finalized_number}, using head")
    
    return safe_hash, finalized_hash


def load_jwt_secret(jwt_file: str) -> str:
    """
    Load and validate JWT secret from file.
    
    Args:
        jwt_file: Path to JWT secret file
    
    Returns:
        JWT secret as hex string
    
    Raises:
        JWTError: If the file cannot be read or secret is invalid
    """
    try:
        with open(jwt_file, 'r') as f:
            jwt_secret = f.read().strip()
    except FileNotFoundError:
        raise JWTError(f"JWT file not found: {jwt_file}")
    except PermissionError:
        raise JWTError(f"Permission denied reading JWT file: {jwt_file}")
    except Exception as e:
        raise JWTError(f"Error reading JWT file: {e}")
    
    # Remove 0x prefix if present
    if jwt_secret.startswith('0x') or jwt_secret.startswith('0X'):
        jwt_secret = jwt_secret[2:]
    
    # Remove whitespace and newlines
    jwt_secret = ''.join(jwt_secret.split())
    
    if len(jwt_secret) != 64:
        raise JWTError(
            f"JWT secret must be exactly 64 hex characters (32 bytes), "
            f"got {len(jwt_secret)} characters"
        )
    
    # Validate hex
    try:
        bytes.fromhex(jwt_secret)
    except ValueError:
        raise JWTError("JWT secret contains invalid hex characters")
    
    return jwt_secret


def print_banner(config: NetworkConfig):
    """Print startup banner"""
    print("=" * 60)
    print("Reth FCU Feeder for XDC Network")
    print("=" * 60)
    print(f"Network:     {config.name} (ID: {config.network_id})")
    print(f"Block Time:  ~{config.block_time_seconds}s")
    print(f"Safe Offset: -{config.safe_block_offset} blocks")
    print(f"Finalized:   -{config.finalized_block_offset} blocks")
    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description="Reth FCU Feeder for XDC Pre-Merge Chains",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Mainnet with explicit settings
  %(prog)s --source http://xdc-node:8547 --target http://reth:8551 --jwt-file /etc/reth/jwt.hex --network mainnet

  # Apothem testnet
  %(prog)s --source http://apothem-node:8548 --target http://reth:8552 --jwt-file /etc/reth/jwt.hex --network apothem

  # With verbose logging
  %(prog)s -v --network mainnet --jwt-file ./jwt.hex

  # Custom interval and error threshold
  %(prog)s --network mainnet --interval 1 --max-errors 10 --jwt-file ./jwt.hex
        """
    )
    
    # Network selection
    parser.add_argument(
        "--network", "-n",
        default="mainnet",
        help="XDC Network to connect to (mainnet, apothem, devnet). Default: mainnet"
    )
    
    # RPC endpoints
    parser.add_argument(
        "--source", "-s",
        help="Source RPC URL (synced XDC node). Uses network default if not specified."
    )
    parser.add_argument(
        "--target", "-t",
        help="Target Engine API URL (Reth authrpc). Uses network default if not specified."
    )
    
    # Authentication
    parser.add_argument(
        "--jwt-file", "-j",
        required=True,
        help="Path to JWT secret hex file (required)"
    )
    
    # Polling settings
    parser.add_argument(
        "--interval", "-i",
        type=int,
        default=2,
        help="Polling interval in seconds. Default: 2"
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=10,
        help="RPC request timeout in seconds. Default: 10"
    )
    
    # Error handling
    parser.add_argument(
        "--max-errors",
        type=int,
        default=5,
        help="Maximum consecutive errors before backoff. Default: 5"
    )
    parser.add_argument(
        "--backoff-seconds",
        type=int,
        default=30,
        help="Backoff duration after max errors. Default: 30"
    )
    
    # Output control
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose (DEBUG) logging"
    )
    parser.add_argument(
        "--quiet", "-q",
        action="store_true",
        help="Only log warnings and errors"
    )
    
    # Fork choice settings
    parser.add_argument(
        "--sync-all",
        action="store_true",
        help="Send all blocks (not just new ones)"
    )
    parser.add_argument(
        "--head-only",
        action="store_true",
        help="Use head hash for safe and finalized (not recommended)"
    )
    
    args = parser.parse_args()
    
    # Setup logging level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
        logger.debug("Verbose logging enabled")
    elif args.quiet:
        logging.getLogger().setLevel(logging.WARNING)
    
    # Parse network
    try:
        network_type = NetworkType.from_string(args.network)
        config = NETWORK_CONFIGS[network_type]
    except ValueError as e:
        logger.error(f"Invalid network: {e}")
        sys.exit(1)
    
    # Determine RPC URLs
    source_rpc = args.source or config.default_source_rpc
    target_auth = args.target or config.default_target_authrpc
    
    # Load JWT secret
    try:
        jwt_secret = load_jwt_secret(args.jwt_file)
        logger.debug(f"Loaded JWT secret from {args.jwt_file}")
    except JWTError as e:
        logger.error(f"JWT Error: {e}")
        sys.exit(1)
    
    # Print banner
    print_banner(config)
    print(f"Source RPC:  {source_rpc}")
    print(f"Target Auth: {target_auth}")
    print(f"Interval:    {args.interval}s")
    print(f"JWT File:    {args.jwt_file}")
    print("=" * 60)
    print()
    
    # State tracking
    last_hash: Optional[str] = None
    last_number: int = 0
    consecutive_errors = 0
    total_updates = 0
    start_time = time.time()
    
    # Setup signal handling for graceful shutdown
    shutdown_requested = False
    
    def signal_handler(signum, frame):
        nonlocal shutdown_requested
        shutdown_requested = True
        logger.info("Shutdown requested, finishing current iteration...")
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logger.info("Starting FCU feeder loop...")
    
    while not shutdown_requested:
        try:
            # Get latest block from source
            block = get_latest_block(source_rpc, timeout=args.timeout)
            if not block:
                consecutive_errors += 1
                logger.warning(f"No block from source (error {consecutive_errors}/{args.max_errors})")
                
                if consecutive_errors >= args.max_errors:
                    logger.error(f"Too many consecutive errors, backing off for {args.backoff_seconds}s")
                    time.sleep(args.backoff_seconds)
                    consecutive_errors = 0
                else:
                    time.sleep(args.interval)
                continue
            
            block_hash = block["hash"]
            block_number_hex = block.get("number", "0x0")
            block_number = int(block_number_hex, 16) if isinstance(block_number_hex, str) else block_number_hex
            
            # Skip if same block (unless --sync-all)
            if block_hash == last_hash and not args.sync_all:
                logger.debug(f"Same block #{block_number}, skipping")
                time.sleep(args.interval)
                continue
            
            # Create fresh JWT (must be regenerated as iat expires)
            jwt_token = create_jwt(jwt_secret)
            
            # Calculate safe and finalized hashes
            if args.head_only:
                safe_hash = block_hash
                finalized_hash = block_hash
            else:
                safe_hash, finalized_hash = calculate_safe_finalized_hashes(
                    source_rpc, block_number, block_hash, config
                )
            
            # Send FCU
            success, status, _ = send_forkchoice_update(
                target_auth, jwt_token, block_hash, safe_hash, finalized_hash,
                timeout=args.timeout
            )
            
            # Process result
            if success:
                consecutive_errors = 0
                total_updates += 1
                
                short_hash = block_hash[:16] + "..."
                short_safe = safe_hash[:8] + "..."
                short_final = finalized_hash[:8] + "..."
                
                logger.info(
                    f"Block #{block_number} ({short_hash}) -> {status} | "
                    f"safe: {short_safe}, finalized: {short_final}"
                )
            else:
                consecutive_errors += 1
                logger.error(
                    f"FCU failed for block #{block_number} ({block_hash[:16]}...): {status} "
                    f"(error {consecutive_errors}/{args.max_errors})"
                )
            
            last_hash = block_hash
            last_number = block_number
            
            # Backoff on repeated errors
            if consecutive_errors >= args.max_errors:
                logger.error(f"Error threshold reached, backing off for {args.backoff_seconds}s")
                time.sleep(args.backoff_seconds)
                consecutive_errors = 0
            else:
                time.sleep(args.interval)
                
        except KeyboardInterrupt:
            logger.info("Interrupted by user")
            break
        except Exception as e:
            logger.exception(f"Unexpected error in main loop: {e}")
            consecutive_errors += 1
            time.sleep(args.interval)
    
    # Print statistics
    elapsed = time.time() - start_time
    logger.info("=" * 60)
    logger.info("FCU Feeder shutdown")
    logger.info(f"Total updates: {total_updates}")
    logger.info(f"Runtime: {elapsed:.1f}s")
    if elapsed > 0:
        logger.info(f"Rate: {total_updates / elapsed:.2f} updates/sec")
    logger.info("=" * 60)


if __name__ == "__main__":
    main()
