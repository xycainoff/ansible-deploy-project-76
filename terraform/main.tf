provider "aws" {
    region = "eu-central-1"
}

### Define locals for referring in configuration
locals {
    ssh_port = 22
    http_port = 80
    https_port = 443
    protocol = "tcp"
    all_cidr_block = "0.0.0.0/0"
}

### Domain and HTTPS certificate
variable "root_domain" {}

data "aws_route53_zone" "my_domain" {
    name = var.root_domain
}

resource "aws_route53_record" "lb" {
    zone_id = data.aws_route53_zone.my_domain.zone_id
    name = "aws.${data.aws_route53_zone.my_domain.name}"
    type = "A"
    alias {
        name = aws_lb.lb.dns_name
        zone_id = aws_lb.lb.zone_id
        evaluate_target_health = true
    }
}

resource "aws_acm_certificate" "cert" {
    domain_name = aws_route53_record.lb.fqdn
    validation_method = "DNS"
    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_route53_record" "domain_ownership_check" {
    for_each = {
        for i in aws_acm_certificate.cert.domain_validation_options : i.domain_name => {
            name = i.resource_record_name
            record = i.resource_record_value
            type = i.resource_record_type
        }
    }
    zone_id = data.aws_route53_zone.my_domain.zone_id
    name = each.value.name
    records = [each.value.record]
    type = each.value.type
    ttl = 60
}

resource "aws_acm_certificate_validation" "my_domain_validation" {
    certificate_arn = aws_acm_certificate.cert.arn
    validation_record_fqdns = [for record in aws_route53_record.domain_ownership_check : record.fqdn]
}

### SSH key to use with VMs
resource "aws_key_pair" "xycainoff" {
    key_name    = "my_personal_key"
    public_key  = file("~/.ssh/id_rsa.pub")
}

### Data Sources to get info from AWS for referring in configuration
data "aws_vpc" "default" {
    default = true
}

data "aws_subnets" "default" {
    filter {
        name = "vpc-id"
        values = [data.aws_vpc.default.id]
    }
}

### Security Groups for use with VMs and Load Balancer
resource "aws_security_group" "lb" {
    name = "LB_Security_Group"
}

resource "aws_vpc_security_group_ingress_rule" "allow_https" {
    security_group_id = aws_security_group.lb.id
    to_port = local.https_port
    from_port = local.https_port
    ip_protocol = local.protocol
    cidr_ipv4 = local.all_cidr_block
}

resource "aws_vpc_security_group_egress_rule" "allow_egress_lb" {
    security_group_id = aws_security_group.lb.id
    ip_protocol = "-1"
    cidr_ipv4 = local.all_cidr_block
}

resource "aws_security_group" "vm" {
    name = "VM_Security_Group"
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
    security_group_id = aws_security_group.vm.id
    to_port = local.ssh_port
    from_port = local.ssh_port
    ip_protocol = local.protocol
    cidr_ipv4 = local.all_cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "allow_http" {
    security_group_id = aws_security_group.vm.id
    to_port = local.http_port
    from_port = local.http_port
    ip_protocol = local.protocol
    cidr_ipv4 = local.all_cidr_block
}

resource "aws_vpc_security_group_egress_rule" "allow_egress_vm" {
    security_group_id = aws_security_group.vm.id
    ip_protocol = "-1"
    cidr_ipv4 = local.all_cidr_block
}

resource "aws_security_group" "db" {
    name = "DB_Security_Group"
}

resource "aws_vpc_security_group_ingress_rule" "allow_ingress_from_vm" {
    security_group_id = aws_security_group.db.id
    referenced_security_group_id = aws_security_group.vm.id
    ip_protocol = "-1"
}

### VMs
resource "aws_instance" "backend" {
    ami        = "ami-08d034851b38dcf94"
    instance_type   = "t2.micro"
    count = 2
    vpc_security_group_ids = [aws_security_group.vm.id]
    key_name = aws_key_pair.xycainoff.id
}

output "VMs_addresses" {
    value = aws_instance.backend[*].public_ip
}

### Load Balancer
resource "aws_lb" "lb" {
    subnets = data.aws_subnets.default.ids
    security_groups = [aws_security_group.lb.id]
}

resource "aws_lb_listener" "lb_https_listener" {
    load_balancer_arn = aws_lb.lb.arn
    port = local.https_port
    protocol = "HTTPS"
    certificate_arn = aws_acm_certificate_validation.my_domain_validation.certificate_arn
    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.lb_target.arn
    }
}

resource "aws_lb_target_group" "lb_target" {
    port = local.http_port
    protocol = "HTTP"
    vpc_id = data.aws_vpc.default.id
    health_check {
        interval = 10
    }
}

resource "aws_lb_target_group_attachment" "lb_target_attachment" {
    for_each = { for i,j in aws_instance.backend : i=>j }
    target_group_arn = aws_lb_target_group.lb_target.arn
    target_id = each.value.id
}

### DB managed by AWS
variable "db_username" {
    sensitive = true
}

variable "db_password" {
    sensitive = true
}

variable "db_engine" {}

variable "db_name" {}

resource "aws_db_instance" "db" {
    vpc_security_group_ids = [aws_security_group.db.id]
    skip_final_snapshot = true
    instance_class = "db.t4g.micro"
    engine = var.db_engine
    allocated_storage = 5
    db_name = var.db_name
    username = var.db_username
    password = var.db_password
}

resource "local_file" "db_info" {
    content = jsonencode({
        "REDMINE_DB_DATABASE" = aws_db_instance.db.db_name
        "REDMINE_DB_POSTGRES" = aws_db_instance.db.address
        "REDMINE_DB_PORT" = tostring(aws_db_instance.db.port)
        "REDMINE_DB_USERNAME" = aws_db_instance.db.username
        "REDMINE_DB_PASSWORD" = var.db_password
    })
    filename = "${path.module}/../db_info.json"
    file_permission = "0444"
}
