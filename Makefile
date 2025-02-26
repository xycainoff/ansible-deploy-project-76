# Makefile
up: # Create infrastructure
	cd terraform && tofu init
	cd terraform && tofu apply -target=aws_route53_record.lb -target=aws_acm_certificate.cert
	cd terraform && tofu apply
	echo '[webservers]' > inventory.ini && jq --raw-output '.outputs.VMs_addresses.value[]' terraform/terraform.tfstate >> inventory.ini

down: # Destroy infrastructure
	tofu destroy

deploy: # Run ansible playbook
	ansible-playbook playbook.yml

run:
	$(MAKE) up
	$(MAKE) deploy
