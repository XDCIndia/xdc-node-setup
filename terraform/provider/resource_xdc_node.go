package main

import (
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/schema"
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/validation"
)

func resourceXDCNode() *schema.Resource {
	return &schema.Resource{
		Description: "Manages an XDC node instance.",
		Create:      resourceXDCNodeCreate,
		Read:        resourceXDCNodeRead,
		Update:      resourceXDCNodeUpdate,
		Delete:      resourceXDCNodeDelete,
		Importer: &schema.ResourceImporter{
			StateContext: schema.ImportStatePassthroughContext,
		},
		Schema: map[string]*schema.Schema{
			"name": {
				Type:        schema.TypeString,
				Required:    true,
				Description: "Name of the XDC node.",
			},
			"network": {
				Type:             schema.TypeString,
				Required:         true,
				ForceNew:         true,
				ValidateFunc:     validation.StringInSlice([]string{"mainnet", "testnet", "devnet"}, false),
				Description:      "Network type (mainnet, testnet, devnet).",
			},
			"client": {
				Type:             schema.TypeString,
				Optional:         true,
				Default:          "xdcchain",
				ValidateFunc:     validation.StringInSlice([]string{"xdcchain", "xinfinorg"}, false),
				Description:      "Client implementation to use.",
			},
			"data_dir": {
				Type:        schema.TypeString,
				Optional:    true,
				Default:     "/data/xdc",
				Description: "Data directory for blockchain data.",
			},
			"rpc_enabled": {
				Type:        schema.TypeBool,
				Optional:    true,
				Default:     true,
				Description: "Enable RPC interface.",
			},
			"rpc_port": {
				Type:         schema.TypeInt,
				Optional:     true,
				Default:      8545,
				ValidateFunc: validation.IsPortNumber,
				Description:  "RPC port.",
			},
			"ws_enabled": {
				Type:        schema.TypeBool,
				Optional:    true,
				Default:     false,
				Description: "Enable WebSocket interface.",
			},
			"ws_port": {
				Type:         schema.TypeInt,
				Optional:     true,
				Default:      8546,
				ValidateFunc: validation.IsPortNumber,
				Description:  "WebSocket port.",
			},
			"p2p_port": {
				Type:         schema.TypeInt,
				Optional:     true,
				Default:      30303,
				ValidateFunc: validation.IsPortNumber,
				Description:  "P2P discovery port.",
			},
			"extra_flags": {
				Type:        schema.TypeList,
				Optional:    true,
				Elem:        &schema.Schema{Type: schema.TypeString},
				Description: "Additional command-line flags.",
			},
			// Computed
			"enode": {
				Type:        schema.TypeString,
				Computed:    true,
				Description: "Enode URL for peer connections.",
			},
			"status": {
				Type:        schema.TypeString,
				Computed:    true,
				Description: "Current node status.",
			},
		},
	}
}

func resourceXDCNodeCreate(d *schema.ResourceData, meta interface{}) error {
	// TODO: Implement node creation via API client
	d.SetId(d.Get("name").(string))
	return resourceXDCNodeRead(d, meta)
}

func resourceXDCNodeRead(d *schema.ResourceData, meta interface{}) error {
	// TODO: Implement node state read
	return nil
}

func resourceXDCNodeUpdate(d *schema.ResourceData, meta interface{}) error {
	// TODO: Implement node update
	return resourceXDCNodeRead(d, meta)
}

func resourceXDCNodeDelete(d *schema.ResourceData, meta interface{}) error {
	// TODO: Implement node deletion
	d.SetId("")
	return nil
}
