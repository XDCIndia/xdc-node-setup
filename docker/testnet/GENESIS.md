# Testnet (Apothem) Genesis

The testnet uses a different genesis file than mainnet. 

To obtain the official Apothem testnet genesis:

1. Download from XDC official repository:
   ```bash
   curl -o genesis.json https://raw.githubusercontent.com/XinFinOrg/XDPoSChain/master/genesis/testnet.json
   ```

2. Or copy from the XDC Docker image:
   ```bash
   docker run --rm xinfinorg/xdposchain:v2.6.8 cat /work/genesis.json > genesis.json
   ```

3. Or visit: https://github.com/XinFinOrg/XDPoSChain/tree/master/genesis

**Note**: The genesis file is required for initial node setup. Without it, the node cannot initialize properly.
