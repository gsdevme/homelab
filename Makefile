.PHONY: all
default: all;

ci:
	ssh -i .ansible root@172.16.16.8 "uptime"
	cd ansible/ && ansible-playbook -i hosts.yml site.yml --private-key ../.ansible --vault-password-file ../ansible.password
	cd kubernetes/ && kubectl apply -f cert-manager
	cd kubernetes/ && kubectl apply -f letsencrypt
