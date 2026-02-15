package main

import (
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/schema"
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/validation"
)

func resourceXDCMonitor() *schema.Resource {
	return &schema.Resource{
		Description: "Configures monitoring for an XDC node.",
		Create:      resourceXDCMonitorCreate,
		Read:        resourceXDCMonitorRead,
		Update:      resourceXDCMonitorUpdate,
		Delete:      resourceXDCMonitorDelete,
		Schema: map[string]*schema.Schema{
			"node_id": {
				Type:        schema.TypeString,
				Required:    true,
				Description: "ID of the XDC node to monitor.",
			},
			"metrics_enabled": {
				Type:        schema.TypeBool,
				Optional:    true,
				Default:     true,
				Description: "Enable Prometheus metrics export.",
			},
			"metrics_port": {
				Type:         schema.TypeInt,
				Optional:     true,
				Default:      9090,
				ValidateFunc: validation.IsPortNumber,
				Description:  "Prometheus metrics port.",
			},
			"alert_email": {
				Type:        schema.TypeString,
				Optional:    true,
				Description: "Email address for alerts.",
			},
			"alert_webhook": {
				Type:        schema.TypeString,
				Optional:    true,
				Description: "Webhook URL for alerts (Slack, Discord, etc.).",
			},
			"health_check_interval": {
				Type:         schema.TypeInt,
				Optional:     true,
				Default:      60,
				ValidateFunc: validation.IntBetween(10, 3600),
				Description:  "Health check interval in seconds.",
			},
			"alert_rules": {
				Type:     schema.TypeList,
				Optional: true,
				Elem: &schema.Resource{
					Schema: map[string]*schema.Schema{
						"name": {Type: schema.TypeString, Required: true},
						"condition": {Type: schema.TypeString, Required: true},
						"threshold": {Type: schema.TypeFloat, Required: true},
						"severity": {
							Type:         schema.TypeString,
							Optional:     true,
							Default:      "warning",
							ValidateFunc: validation.StringInSlice([]string{"info", "warning", "critical"}, false),
						},
					},
				},
				Description: "Custom alert rules.",
			},
		},
	}
}

func resourceXDCMonitorCreate(d *schema.ResourceData, meta interface{}) error {
	d.SetId(d.Get("node_id").(string) + "-monitor")
	return resourceXDCMonitorRead(d, meta)
}

func resourceXDCMonitorRead(d *schema.ResourceData, meta interface{}) error {
	return nil
}

func resourceXDCMonitorUpdate(d *schema.ResourceData, meta interface{}) error {
	return resourceXDCMonitorRead(d, meta)
}

func resourceXDCMonitorDelete(d *schema.ResourceData, meta interface{}) error {
	d.SetId("")
	return nil
}
