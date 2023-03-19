resource "aws_kms_key" "ca" {
  description = "${var.app}/${var.env} certificate authority"

  tags = {
    Application = var.app
    Environment = var.env
  }
}

resource "aws_kms_alias" "ca" {
  name          = "alias/${var.app}-${var.env}-ca"
  target_key_id = aws_kms_key.ca.key_id
}

resource "aws_ssm_parameter" "ca-private-key" {
  name   = "/${lower(var.app)}/${var.env}/ca_private_key"
  type   = "SecureString"
  key_id = aws_kms_alias.ca.name
  value  = "CHANGEME"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "client-private-key" {
  name   = "/${lower(var.app)}/${var.env}/client_private_key"
  type   = "SecureString"
  key_id = aws_kms_alias.ca.name
  value  = "CHANGEME"

  lifecycle {
    ignore_changes = [value]
  }
}

locals {
  ten_years   = 87600
  five_years  = 43830
  ninety_days = 2160
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem   = aws_ssm_parameter.ca-private-key.value
  is_ca_certificate = true

  subject {
    common_name         = "vpn.example.com"
    organization        = "Acme"
    organizational_unit = "Engineering"
    country             = "USA"
  }

  validity_period_hours = local.ten_years
  early_renewal_hours   = local.ninety_days

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "code_signing",
    "server_auth",
    "client_auth",
    "digital_signature",
    "key_encipherment",
  ]
}

resource "aws_acm_certificate" "ca" {
  private_key      = aws_ssm_parameter.ca-private-key.value
  certificate_body = tls_self_signed_cert.ca.cert_pem
  tags = {
    Application = var.app
    Environment = var.env
  }
}

resource "local_file" "ca-certificate" {
  content         = tls_self_signed_cert.ca.cert_pem
  filename        = "${path.module}/certificates/ca.pem"
  file_permission = "0666"
}


resource "tls_cert_request" "client" {
  private_key_pem = aws_ssm_parameter.client-private-key.value

  subject {
    common_name         = "client1.vpn.example.com"
    organization        = "Acme"
    organizational_unit = "Engineering"
    country             = "USA"
  }
}

resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = aws_ssm_parameter.ca-private-key.value
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = local.five_years
  early_renewal_hours   = local.ninety_days

  allowed_uses = [
    "client_auth",
  ]
}

resource "local_file" "client-certificate" {
  content         = tls_locally_signed_cert.client.cert_pem
  filename        = "${path.module}/certificates/client.pem"
  file_permission = "0666"
}
