# Core settings
variable count {}
variable name_prefix {}
variable vcpu {}
variable memory {}
variable disk_size {}
variable storage_pool {}

# SSH settings
variable ssh_key {}
variable ssh_user {}

# Network settings
#variable network_id {}
variable ip_if1 { type = "list" }
variable ip_if2 { type = "list" }
variable network_cfg {}

# Disk settings
variable template_vol_id {}
variable extra_disk_size { default = 0 }

# Bootstrap settings
variable bootstrap_file {}
variable kubeadm_token {}
variable node_labels { type = "list" }
variable node_taints { type = "list" }
variable master_ip { default = "" }
variable cloud_init_cfg {}

# Bootstrap
data "template_file" "instance_bootstrap" {
  count    = "${var.count > 0 ? 1 : 0}"
  template = "${file("${path.root}/../${var.bootstrap_file }")}"

  vars {
    kubeadm_token = "${var.kubeadm_token}"
    master_ip     = "${var.master_ip}"
    private_ip    = "${element(var.ip_if1, count.index)}"
    node_labels   = "${join(",", var.node_labels)}"
    node_taints   = "${join(",", var.node_taints)}"
    ssh_user      = "${var.ssh_user}"
  }
}

# Create a password
resource "random_id" "password" {
 byte_length = 6
}

# Create cloud init config file
data "template_file" "user_data" {
  count    = "${var.count > 0 ? 1 : 0}"
  template = "${file("${path.root}/../${var.cloud_init_cfg }")}"

  vars{
    bootstrap_script_content = "${base64encode(data.template_file.instance_bootstrap.rendered)}"
    ssh_key                  = "${file(var.ssh_key)}"
    hostname                 = "${var.name_prefix}-${format("%03d", count.index)}"
    password                 = "${random_id.password.b64_url}"
  }
}

# Create network interface init config file
data "template_file" "network_config" {
  count     = "${var.count > 0 ? 1 : 0}"
  template = "${file("${path.root}/../${var.network_cfg }")}"

  vars{
    ip_if1  = "${element(var.ip_if1, count.index)}"
    ip_if2 = "${element(var.ip_if2, count.index)}"
  }
}

# Create cloud-init iso image
resource "libvirt_cloudinit_disk" "commoninit" {
  count          = "${var.count > 0 ? 1 : 0}"
  name           = "${var.name_prefix}-cloud-init.iso"
  user_data      = "${data.template_file.user_data.rendered}"
  network_config = "${element(data.template_file.network_config.*.rendered, count.index)}"
  pool           = "${var.storage_pool}"
}

# Create root volume
resource "libvirt_volume" "root_volume" {
  count          = "${var.count}"
  name           = "${var.name_prefix}-vol-${format("%03d", count.index)}"
  base_volume_id = "${var.template_vol_id}"
  size           = "${var.disk_size * 1024 * 1024 * 1024}"
  pool           = "${var.storage_pool}"
}

# Create extra volume
resource "libvirt_volume" "extra_disk" {
  count = "${var.count}"
  name  = "${var.name_prefix}-extra-vol-${format("%03d", count.index)}"
  size  = "${var.extra_disk_size * 1024 * 1024 * 1024}"
  pool  = "${var.storage_pool}"
}

# Create instances
resource "libvirt_domain" "instance" {
  count       = "${var.count}"
  name        = "${var.name_prefix}-${format("%03d", count.index)}"
  vcpu        = "${var.vcpu}"
  memory      = "${var.memory}"

  cloudinit   = "${element(libvirt_cloudinit_disk.commoninit.*.id, count.index)}"

  disk = [
    {
      volume_id = "${element(libvirt_volume.root_volume.*.id, count.index)}"
    },
    {
      volume_id = "${element(libvirt_volume.extra_disk.*.id, count.index)}"
    }
  ]

  network_interface {
    bridge         = "br1"
    # Addresses are set by cloud init network_config
  }

  network_interface {
    bridge         = "br0"
    # Addresses are set by cloud init network_config
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}

# Module outputs
output "extra_disk_device" {
  value = ["/dev/vdb"]
}

#output "local_ip_v4" {
#  value = ["${libvirt_domain.instance.*.network_interface.0.addresses.0}"]
#}
#
#output "public_ip" {
#  # TODO same as internal until creating second network
#  value = ["${libvirt_domain.instance.*.network_interface.0.addresses.0}"]
#}

output "local_ip_v4" {
  value = "${var.ip_if1}"
}

output "public_ip" {
  value = "${var.ip_if2}"
}

output "hostnames" {
  value = ["${libvirt_domain.instance.*.name}"]
}

output "node_labels" {
  value = "${var.node_labels}"
}
