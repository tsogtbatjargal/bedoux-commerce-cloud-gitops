locals {
  project_role_permissions_boundary_arn = "arn:aws:iam::aws:policy/PowerUserAccess"

  tags = {
    project     = "bedoux-commerce-cloud"
    environment = "learning"
  }
}
