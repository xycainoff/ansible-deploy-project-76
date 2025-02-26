### Hexlet tests and linter status:
[![Actions Status](https://github.com/xycainoff/ansible-deploy-project-76/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/xycainoff/ansible-deploy-project-76/actions)
This project deploys docker image of Redmine on prepared AWS cloud infrastructure using Ansible.
All needed infactructure created by Terraform. It includes pair of VMs, load balancer and managed database service. Terraform config files stored in 'terraform' directory.
Deploing database needs defining username and password and have to be specified in terraform variables. All DB related info to be used further by Ansible will be saved as json file in root directory of this project.
This project assumes you already have DNS zone defined in AWS Route53 service. "aws" subdomain will be created for deployed web app. Root domain name has to be specified in terraform variables.
Load balancer listener uses HTTPS, so it needs certificate. For that purpose this project uses AWS ACM service. It needs to verify domain ownership first to issue a certificate, by publishing special records in DNS for domain. Because of that we need to create corresponding DNS record first and only after that apply all other steps. 
Makefile define all neccesery steps in correct order so it is better to use "make up" command to bring all infrastrucrure up.
Running 'make up' will also generate 'inventory.ini' file in root directory of this project to be used by Ansible.
Running 'make deploy' will run ansible playbook deploying Redmine on VMs.
Command 'make run' will execute all needed steps.
