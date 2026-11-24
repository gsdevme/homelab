# VM images built weekly by this repo's GitHub Actions workflow and
# published as release assets. The node downloads them itself, through the
# API, as `import` content that modules/vm imports as a root disk.
#
# overwrite = false: a re-downloaded asset of the same release is the same
# file, so a changed size upstream is no reason to replace it.
# overwrite_unmanaged = true: if the state is lost while the file stays on
# the node, a fresh apply takes the file over instead of failing on it.
# create_before_destroy: the file name carries the tag, so on a bump the new
# file is downloaded before the old one is deleted, and a bump to a tag that
# does not exist fails without removing the current image.
locals {
  image_files = {
    debian = "debian-13-homelab-${var.images_release}.qcow2"
    alpine = "alpine-3.23-homelab-${var.images_release}.qcow2"
  }

  image_urls = {
    for os, file in local.image_files :
    os => "https://github.com/${var.images_repository}/releases/download/${var.images_release}/${file}"
  }
}

resource "proxmox_download_file" "debian_vm" {
  node_name           = var.node_name
  datastore_id        = var.images_datastore
  content_type        = "import"
  url                 = local.image_urls.debian
  file_name           = local.image_files.debian
  overwrite           = false
  overwrite_unmanaged = true

  lifecycle {
    create_before_destroy = true
  }
}

resource "proxmox_download_file" "alpine_vm" {
  node_name           = var.node_name
  datastore_id        = var.images_datastore
  content_type        = "import"
  url                 = local.image_urls.alpine
  file_name           = local.image_files.alpine
  overwrite           = false
  overwrite_unmanaged = true

  lifecycle {
    create_before_destroy = true
  }
}
