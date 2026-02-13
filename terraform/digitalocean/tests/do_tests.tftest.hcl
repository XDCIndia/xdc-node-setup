terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

run "validate_droplet" {
  command = plan

  variables {
    name       = "xdc-test-node"
    region     = "nyc3"
    size       = "s-4vcpu-8gb"
    ssh_keys   = ["12345678"]
  }

  assert {
    condition     = digitalocean_droplet.xdc_node.size == "s-4vcpu-8gb"
    error_message = "Droplet size should be s-4vcpu-8gb"
  }

  assert {
    condition     = digitalocean_droplet.xdc_node.region == "nyc3"
    error_message = "Droplet region should be nyc3"
  }
}

run "validate_volume" {
  command = plan

  variables {
    volume_size = 500
  }

  assert {
    condition     = digitalocean_volume.xdc_data.size == 500
    error_message = "Volume size should be 500 GB"
  }
}

run "validate_firewall" {
  command = plan

  assert {
    condition     = length(digitalocean_firewall.xdc_node.inbound_rule) >= 3
    error_message = "Firewall should have at least 3 inbound rules"
  }
}