// Copyright 2024 XDC Network. Apache-2.0 License.
// terraform-provider-xdc – custom Terraform provider for XDC node management.

package main

import (
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/schema"
	"github.com/hashicorp/terraform-plugin-sdk/v2/plugin"
)

func main() {
	plugin.Serve(&plugin.ServeOpts{
		ProviderFunc: Provider,
	})
}

// Provider returns the XDC Terraform provider schema.
func Provider() *schema.Provider {
	return &schema.Provider{
		Schema: map[string]*schema.Schema{
			"endpoint": {
				Type:        schema.TypeString,
				Required:    true,
				DefaultFunc: schema.EnvDefaultFunc("XDC_ENDPOINT", "https://rpc.xinfin.network"),
				Description: "XDC network RPC endpoint.",
			},
			"private_key": {
				Type:        schema.TypeString,
				Optional:    true,
				Sensitive:   true,
				DefaultFunc: schema.EnvDefaultFunc("XDC_PRIVATE_KEY", nil),
				Description: "Private key for signing transactions.",
			},
		},
		ResourcesMap: map[string]*schema.Resource{
			"xdc_node":       resourceXDCNode(),
			"xdc_masternode": resourceXDCMasternode(),
			"xdc_backup":     resourceXDCBackup(),
			"xdc_monitor":    resourceXDCMonitor(),
		},
		DataSourcesMap: map[string]*schema.Resource{
			"xdc_network":    dataSourceXDCNetwork(),
			"xdc_validators": dataSourceXDCValidators(),
		},
		ConfigureFunc: providerConfigure,
	}
}

func providerConfigure(d *schema.ResourceData) (interface{}, error) {
	config := &Config{
		Endpoint:   d.Get("endpoint").(string),
		PrivateKey: d.Get("private_key").(string),
	}
	return config.Client()
}

// Config holds provider configuration.
type Config struct {
	Endpoint   string
	PrivateKey string
}

// Client returns an API client for the XDC network.
func (c *Config) Client() (*APIClient, error) {
	return &APIClient{
		Endpoint:   c.Endpoint,
		PrivateKey: c.PrivateKey,
	}, nil
}

// APIClient is the XDC API client used by resources and data sources.
type APIClient struct {
	Endpoint   string
	PrivateKey string
}
