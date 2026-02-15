package main

import (
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/schema"
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/validation"
)

func resourceXDCBackup() *schema.Resource {
	return &schema.Resource{
		Description: "Manages backup schedules for XDC node data.",
		Create:      resourceXDCBackupCreate,
		Read:        resourceXDCBackupRead,
		Update:      resourceXDCBackupUpdate,
		Delete:      resourceXDCBackupDelete,
		Schema: map[string]*schema.Schema{
			"node_id": {
				Type:        schema.TypeString,
				Required:    true,
				Description: "ID of the XDC node to back up.",
			},
			"schedule": {
				Type:        schema.TypeString,
				Required:    true,
				Description: "Cron schedule expression (e.g. '0 2 * * *').",
			},
			"retention_days": {
				Type:         schema.TypeInt,
				Optional:     true,
				Default:      30,
				ValidateFunc: validation.IntBetween(1, 365),
				Description:  "Number of days to retain backups.",
			},
			"destination": {
				Type:             schema.TypeString,
				Required:         true,
				ValidateFunc:     validation.StringInSlice([]string{"s3", "gcs", "local"}, false),
				Description:      "Backup destination type.",
			},
			"destination_path": {
				Type:        schema.TypeString,
				Required:    true,
				Description: "Destination path or bucket URI.",
			},
			"compression": {
				Type:        schema.TypeBool,
				Optional:    true,
				Default:     true,
				Description: "Enable gzip compression.",
			},
			// Computed
			"last_backup": {
				Type:        schema.TypeString,
				Computed:    true,
				Description: "Timestamp of the last successful backup.",
			},
		},
	}
}

func resourceXDCBackupCreate(d *schema.ResourceData, meta interface{}) error {
	d.SetId(d.Get("node_id").(string) + "-backup")
	return resourceXDCBackupRead(d, meta)
}

func resourceXDCBackupRead(d *schema.ResourceData, meta interface{}) error {
	return nil
}

func resourceXDCBackupUpdate(d *schema.ResourceData, meta interface{}) error {
	return resourceXDCBackupRead(d, meta)
}

func resourceXDCBackupDelete(d *schema.ResourceData, meta interface{}) error {
	d.SetId("")
	return nil
}
