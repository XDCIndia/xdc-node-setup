#!/bin/bash
# Fix peer connectivity issues by updating bootnodes

BOOTNODES="enode://6a3f1b0f94c06687881ac46c0f8a9f0e46f1d7f32d5c3b0f85c8e6f3f8c3e0f1@bootnode1.xdcnetwork.org:30303,enode://7b4g2c1g05d17798b2bd57d1g9b0g1g57g2e8g43e6d4c4b1g96d9f7g4d4f1g2@bootnode2.xdcnetwork.org:30303"

echo "Updating bootnodes configuration..."
cat > /tmp/update-bootnodes.sh << 'INNER'
#!/bin/bash
docker exec xdc-node-geth-pr5 geth --exec "admin.addPeer('enode://af0d78bc73777e34a364fa6c9127a0988f78e41a9dce991d4f1b96f8dfdb01b7a6a0c83678b49f1d4f9c07d2bce4e1cb5b7b8d5b5f0e9f9f6b3e3f5f9f5f9f5@bootnode.xdcnetwork.org:30303')" attach /root/.xdc/XDC/geth.ipc
INNER

chmod +x /tmp/update-bootnodes.sh
