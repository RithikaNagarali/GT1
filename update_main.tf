# TERRAFORM AND PROVIDER DETAILS
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.51.0"
    }
  }
}
provider "azurerm" {

    client_id       = "5e636370-3b89-4d4a-8742-0cc9346f9308"
    tenant_id       = "be4fe9dc-a5f8-4649-b927-a49592994082"
    subscription_id = "d786964d-240f-4088-9247-4ba08f0c47d0"
    client_secret   = "qJH8Q~Klh5-PcjIslNfFcSi9hsUX2YBjFTlYGbtz"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

variable "vm_admin_username" {}
variable "vm_admin_password" {}

# RESOURCE GROUP
resource "azurerm_resource_group" "test" {
  name     = "RG-Terraform"
  location = "East US"

  tags = {
    environment = "group-demo"
  }
}

# VIRTUAL NETWORK
resource "azurerm_virtual_network" "VNet" {
  name                = "VNet"
  address_space       = ["192.168.0.0/18"]
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
}

# SUBNETS
variable "subnet-names" {
  type = list(string)
  default = ["Subnet-Web", "Subnet-App", "Subnet-DB"]
}

resource "azurerm_subnet" "Subnets" {
  count                = length(var.subnet-names)
  name                 = var.subnet-names[count.index]
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.VNet.name
  address_prefixes     = count.index == 0 ? ["192.168.0.0/26"] : count.index == 1 ? ["192.168.0.64/28"] : ["192.168.0.128/25"]
}

#NETWORK INTERFACE 
resource "azurerm_network_interface" "nic" {
  count               = length(var.subnet-names)
  name                = count.index == 0 ? "NIC-Web" : count.index == 1 ? "NIC-App" : "NIC-DB"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  ip_configuration {
    name      = "testconfiguration1"
    subnet_id = azurerm_subnet.Subnets[count.index].id
    private_ip_address_allocation = "Dynamic"
  }
}

# CENT OS - VIRTUAL MACHINEs
resource "azurerm_virtual_machine" "AZURE-VM" {
  count                 = length(var.subnet-names)
  name                  = count.index == 0 ? "VM-Web" : count.index == 1 ? "VM-App" : "VM-DB"
  location              = azurerm_resource_group.test.location
  resource_group_name   = azurerm_resource_group.test.name
  network_interface_ids = [azurerm_network_interface.nic[count.index].id]
  vm_size               = "Standard_B1s"

  storage_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.5"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk-${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }
  os_profile {
    computer_name  = "hostname-${count.index}"
    admin_username = var.vm_admin_username
    admin_password = var.vm_admin_password
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }
}

# NETWORK SECURITY GROUP
resource "azurerm_network_security_group" "NSG" {
  count               = length(var.subnet-names)
  name                = "NSG"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  security_rule {
    name                   = "Allow-inbound-for-web-VM"
    priority               = 100
    direction              = "Inbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = 22
    destination_port_range = 22
    source_address_prefix  = "192.168.0.5"
    destination_application_security_group_ids = [azurerm_application_security_group.ASG.id]
  }

  security_rule {
    name                                  = "Allow-outbound-for-web-VM"
    priority                              = 101
    direction                             = "Outbound"
    access                                = "Allow"
    protocol                              = "Tcp"
    source_port_range                     = 22
    destination_port_range                = 22
    destination_address_prefix            = "192.168.0.5"
    source_application_security_group_ids = [azurerm_application_security_group.ASG.id]
  }

  security_rule {
    name                                       = "Allow-inbound-for-DB-ASG"
    priority                                   = 102
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = 22
    destination_port_range                     = 22
    source_application_security_group_ids      = [azurerm_application_security_group.ASG.id]
    destination_application_security_group_ids = [azurerm_application_security_group.ASG-DB.id]
  }


  security_rule {
    name                                       = "Allow-outbound-for-DB-ASG"
    priority                                   = 103
    direction                                  = "Outbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = 22
    destination_port_range                     = 22
    source_application_security_group_ids      = [azurerm_application_security_group.ASG-DB.id]
    destination_application_security_group_ids = [azurerm_application_security_group.ASG.id]

  }

  security_rule {
    name                                  = "Allow-inbound-for-bastion-host"
    priority                              = 104
    direction                             = "Inbound"
    access                                = "Allow"
    protocol                              = "Tcp"
    source_port_range                     = 443
    destination_port_range                = 443
    source_application_security_group_ids = [azurerm_application_security_group.ASG.id]
    destination_address_prefix            = "*"

  }
  security_rule {
    name                                       = "Allow-outbound-for-bastion-host"
    priority                                   = 105
    direction                                  = "Outbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = 443
    destination_port_range                     = 443
    source_address_prefix                      = "*"
    destination_application_security_group_ids = [azurerm_application_security_group.ASG.id]
  }

}

resource "azurerm_subnet_network_security_group_association" "Associate-SG" {
  count                     = length(var.subnet-names)
  subnet_id                 = azurerm_subnet.Subnets[count.index].id
  network_security_group_id = azurerm_network_security_group.NSG[count.index].id

  depends_on = [azurerm_subnet.Subnets]
}

#APPLICATION SECURITY GROUP
resource "azurerm_application_security_group" "ASG" {
  name                = "ASG"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
}

resource "azurerm_network_interface_application_security_group_association" "application_security_group_association" {
  count                         = (length(var.subnet-names)) - 1
  network_interface_id          = azurerm_network_interface.nic[count.index].id
  application_security_group_id = azurerm_application_security_group.ASG.id
}

resource "azurerm_application_security_group" "ASG-DB" {
  name                = "ASG-DB"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
}

resource "azurerm_network_interface_application_security_group_association" "application_security_group_association-DB" {
  count                         = (length(var.subnet-names)) - 2
  network_interface_id          = azurerm_network_interface.nic[2].id
  application_security_group_id = azurerm_application_security_group.ASG-DB.id
}

# WINDOWS-VM-----------------------------------------------------------------------------------------------------

# PUBLIC IP ADDRESS
resource "azurerm_public_ip" "public-ip" {
  name                = "public-ip"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  allocation_method   = "Dynamic"
}

#NETWORK INTERFACE
resource "azurerm_network_interface" "nic-window" {
  name                = "nic-window"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name

  ip_configuration {
    name      = "testconfiguration1"
    subnet_id = azurerm_subnet.Subnets[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.public-ip.id
  }
}

# WINDOWS - VM
resource "azurerm_windows_virtual_machine" "Windows-VM" {
  name                = "Windows-VM"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location
  size                = "Standard_B1s"
  admin_username = var.vm_admin_username
  admin_password = var.vm_admin_password

  network_interface_ids = [
    azurerm_network_interface.nic-window.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

# STANDARD LOAD BALANCER
resource "azurerm_lb" "standard-LB" {
  name                = "standard-LB"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  sku                 = "Standard"

   frontend_ip_configuration {
    name                          = "LB-IP"
    subnet_id                     = azurerm_subnet.Subnets[0].id
    private_ip_address_allocation = "Dynamic"
    }
}

# STANDARD LB - BACKEND POOL
resource "azurerm_lb_backend_address_pool" "BackEndAddressPool" {
  loadbalancer_id = azurerm_lb.standard-LB.id
  name            = "BackEndAddressPool"
}

resource "azurerm_network_interface_backend_address_pool_association" "BackEndAddressPool-association" {
  network_interface_id = azurerm_network_interface.nic[0].id
  ip_configuration_name   = "testconfiguration1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.BackEndAddressPool.id
}
