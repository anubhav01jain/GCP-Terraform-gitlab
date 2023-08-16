terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.78.0"
    }
  }
}

provider "google" {
  project     = "spherical-list-395700"
  region      = "asia-southeast1"
  zone        = "asia-southeast1-b"
  credentials = "./key.json"
}

resource "google_compute_network" "wg_network" {
  name                    = "wg-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "wg_subnetwork" {
  project       = "spherical-list-395700"
  name          = "wg-subnetwork"
  ip_cidr_range = "172.17.1.0/24"
  region        = "asia-southeast1"
  network       = google_compute_network.wg_network.name

  #https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/compute_subnetwork
  #purpose       = "PUBLIC"

  depends_on = [google_compute_network.wg_network]
}
resource "google_compute_subnetwork" "private_subnetwork" {
  project       = "spherical-list-395700"
  name          = "private-subnetwork"
  ip_cidr_range = "172.17.2.0/24"
  region        = "asia-southeast1"
  network       = google_compute_network.wg_network.name
  purpose       = "PRIVATE"

  depends_on = [google_compute_network.wg_network]
}

# create a public ip for nat service
resource "google_compute_address" "nat-ip" {
  name    = "nat-ip"
  project = "spherical-list-395700"
  region  = "asia-southeast1"
}
# create a nat to allow private instances connect to internet
resource "google_compute_router" "nat-router" {
  name    = "nat-router"
  network = google_compute_network.wg_network.name
}
resource "google_compute_router_nat" "nat-gateway" {
  name   = "nat-gateway"
  router = google_compute_router.nat-router.name

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = [google_compute_address.nat-ip.self_link]

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS" #"ALL_SUBNETWORKS_ALL_IP_RANGES"
  subnetwork {
    name                    = google_compute_subnetwork.private_subnetwork.id
    source_ip_ranges_to_nat = ["172.17.2.0/24"] # "ALL_IP_RANGES"
  }
  depends_on = [google_compute_address.nat-ip]
}


resource "google_compute_firewall" "wg-firewall" {
  depends_on = [google_compute_subnetwork.wg_subnetwork]

  name    = "default-allow-wg"
  network = "wg-network"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  allow {
    protocol = "udp"
    ports    = ["51820"]
  }
  allow {
    protocol = "icmp"
  }

  // Allow traffic from everywhere to instances with tag
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["wg-server"]
}

resource "google_compute_firewall" "web-firewall" {
  depends_on = [google_compute_subnetwork.private_subnetwork]

  name    = "default-allow-web"
  network = "wg-network"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  allow {
    protocol = "icmp"
  }

  // traffic could come from public subnet or wireguard cidr block
  // we will just be wide here
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-server"]
}

resource "google_compute_instance" "private_vm_instance" {
  depends_on = [google_compute_subnetwork.private_subnetwork]
  name         = "private-vm-1"
  machine_type = "e2-medium"
  project      = "spherical-list-395700"

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/ubuntu-2004-focal-arm64-v20230812"
    }
  }
  metadata_startup_script = "sudo yum -y update; sudo yum -y install epel-release; sudo yum -y install nginx; sudo service nginx start;"
  network_interface {
    network            = "wg-network"
    subnetwork         = "private-subnetwork"
    subnetwork_project = "spherical-list-395700"
    network_ip        = null
    access_config {
    }
  }
  tags = ["web-server"]
}

resource "google_compute_instance" "public_vm_instance" {
  depends_on = [google_compute_subnetwork.wg_subnetwork]
  name         = "public-vm-1"
  machine_type = "e2-medium"
  project      = "spherical-list-395700"

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/ubuntu-2004-focal-arm64-v20230812"
    }
  }
  metadata_startup_script = "sudo yum -y update; sudo yum -y install epel-release; sudo yum -y install nginx; sudo service nginx start;"
  network_interface {
    network            = "wg-network"
    subnetwork         = "wg-subnetwork"
    subnetwork_project = "spherical-list-395700"
    access_config {
    }
  }
  tags = ["wg-server"]
}
