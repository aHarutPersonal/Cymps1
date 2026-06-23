provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "cmpys"
      Env       = var.env
      ManagedBy = "terraform"
    }
  }
}
