provider "aws" {
  region  = var.region
  profile = var.profile

  default_tags {
    tags = {
      Project   = "zrok2"
      ManagedBy = "terraform"
    }
  }
}
