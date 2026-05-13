# =============================================================================
# Terraform Remote State Backend
# Configure via: terraform init -backend-config=backend.hcl
#
# backend.hcl example:
#   endpoint                    = "https://fsn1.your-objectstorage.com"
#   bucket                      = "terraform-state"
#   key                         = "rke2/terraform.tfstate"
#   region                      = "fsn1"
#   access_key                  = "your-hetzner-s3-access-key"
#   secret_key                  = "your-hetzner-s3-secret-key"
#   skip_credentials_validation = true
#   skip_metadata_api_check     = true
#   force_path_style            = true
#
# Or use environment variables:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
# =============================================================================

terraform {
  backend "s3" {
    # All values are configured via backend.hcl or environment variables.
    # Run: terraform init -backend-config=backend.hcl
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
