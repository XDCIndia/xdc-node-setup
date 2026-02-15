package main

import (
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/schema"
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/validation"
)

func resourceXDCMasternode() *schema.Resource {
	return &schema.Resource{
		Description: "Manages an XDC masternode with staking configuration.",
		Create:      resourceXDCMasternodeCreate,
		Read:        resourceXDCMasternodeRead,
		Update:      resourceXDCMasternodeUpdate,
		Delete:      resourceXDCMasternodeDelete,
		Importer: &schema.ResourceImporter{
			StateContext: schema.ImportStatePassthroughContext,
		},
		Schema: map[string]*schema.Schema{
			"name": {
				Type:        schema.TypeString,
				Required:    true,
				Description: "Masternode name.",
			},
			"network": {
				Type:             schema.TypeString,
				Required:         true,
				ForceNew:         true,
				ValidateFunc:     validation.StringInSlice([]string{"mainnet", "testnet"}, false),
				Description:      "Network (mainnet, testnet).",
			},
			"coinbase": {
				Type:        schema.TypeString,
				Required:    true,
				ForceNew:    true,
				Description: "Coinbase address for the masternode.",
			},
			"staking_amount": {
				Type:        schema.TypeString,
				Optional:    true,
				Default:     "10000000",
				Description: "XDC staking amount (default 10M for mainnet).",
			},
			"keystore_path": {
				Type:        schema.TypeString,
				Required:    true,
				Sensitive:   true,
				Description: "Path to the keystore file.",
			},
			// Computed
			"status": {
				Type:        schema.TypeString,
				Computed:    true,
				Description: "Current masternode status.",
			},
			"epoch": {
				Type:        schema.TypeInt,
				Computed:    true,
				Description: "Current epoch number.",
			},
		},
	}
}

func resourceXDCMasternodeCreate(d *schema.ResourceData, meta interface{}) error {
	d.SetId(d.Get("coinbase").(string))
	return resourceXDCMasternodeRead(d, meta)
}

func resourceXDCMasternodeRead(d *schema.ResourceData, meta interface{}) error {
	// TODO: Query masternode status from chain
	return nil
}

func resourceXDCMasternodeUpdate(d *schema.ResourceData, meta interface{}) error {
	return resourceXDCMasternodeRead(d, meta)
}

func resourceXDCMasternodeDelete(d *schema.ResourceData, meta interface{}) error {
	// TODO: Resign masternode
	d.SetId("")
	return nil
}
