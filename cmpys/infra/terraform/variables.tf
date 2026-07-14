variable "region" {
  type    = string
  default = "us-east-1"
}

variable "env" {
  type    = string
  default = "prod"
}

variable "instance_type" {
  type    = string
  default = "t4g.small" # ARM64, ~$6/mo
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key content (paste your ~/.ssh/id_rsa.pub or similar)"
}

variable "gemini_api_key" {
  type      = string
  sensitive = true
}

variable "openai_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "yunwu_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "tavily_api_key" {
  type      = string
  sensitive = true
  default   = ""
}
