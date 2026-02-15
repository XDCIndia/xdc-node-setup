package main

import "github.com/hashicorp/terraform-plugin-sdk/v2/helper/schema"

func dataSourceXDCValidators() *schema.Resource {
	return &schema.Resource{
		Description: "Retrieves the current validator set from the XDC network.",
		Read:        dataSourceXDCValidatorsRead,
		Schema: map[string]*schema.Schema{
			"epoch": {
				Type:        schema.TypeInt,
				Optional:    true,
				Computed:    true,
				Description: "Epoch to query (defaults to current).",
			},
			"validators": {
				Type:     schema.TypeList,
				Computed: true,
				Elem: &schema.Resource{
					Schema: map[string]*schema.Schema{
						"address": {
							Type:        schema.TypeString,
							Computed:    true,
							Description: "Validator address.",
						},
						"capacity": {
							Type:        schema.TypeString,
							Computed:    true,
							Description: "Total staked capacity.",
						},
						"status": {
							Type:        schema.TypeString,
							Computed:    true,
							Description: "Validator status (active, standby, penalty).",
						},
					},
				},
				Description: "List of validators.",
			},
			"total_validators": {
				Type:        schema.TypeInt,
				Computed:    true,
				Description: "Total number of validators.",
			},
		},
	}
}

func dataSourceXDCValidatorsRead(d *schema.ResourceData, meta interface{}) error {
	// TODO: Query validator list from XDC master contract
	d.SetId("xdc-validators")
	return nil
}
