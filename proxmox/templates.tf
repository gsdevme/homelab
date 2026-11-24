# Container templates are downloaded by the Proxmox node itself, through
# the API, so nothing here needs SSH access to the host.
resource "proxmox_download_file" "debian_lxc" {
  node_name    = var.node_name
  datastore_id = var.template_datastore
  content_type = "vztmpl"
  url          = var.debian_lxc_template_url
}
