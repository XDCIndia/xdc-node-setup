package main

import "github.com/hashicorp/terraform-plugin-sdk/v2/helper/schema"

func dataSourceXDCNetwork() *schema.Resource {
	return &schema.Resource{
		Description: "Retrieves information about the XDC network.",
		Read:        dataSourceXDCNetworkRead,
		Schema: map[string]*schema.Schema{
			"network_id": {
				Type:        schema.TypeInt,
				Computed:    true,
				Description: "Network chain ID (50 = mainnet, 51 = testnet).",
			},
			"latest_block": {
				Type:        schema.TypeInt,
				Computed:    true,
				Description: "Latest block number.",
			},
			"current_epoch": {
				Type:        schema.TypeInt,
				Computed:    true,
				Description: "Current epoch number.",
			},
			"gas_price": {
				Type:        schema.TypeString,
				Computed:    true,
				Description: "Current gas price in wei.",
			},
			"peer_count": {
				Type:        schema.TypeInt,
				Computed:    true,
				Description: "Number of connected peers.",
			},
			"syncing": {
				Type:        schema.TypeBool,
				Computed:    true,
				Description: "Whether the node is syncing.",
			},
		},
	}
}

func dataSourceXDCNetworkRead(d *schema.ResourceData, meta interface{}) error {
	// TODO: Query network info via RPC
	d.SetId("xdc-network")
	return nil
}
