.PHONY: all
default: all;

ci:
	#ssh -i .ansible root@172.16.16.8 "uptime"
	#ssh -i .ansible root@172.16.16.9 "uptime"
	#cd ansible/ && ansible-playbook -i hosts.yml site.yml --private-key ../.ansible --vault-password-file ../ansible.password
	cd kubernetes/ && kubectl apply --wait=true -f metallb
	cd kubernetes/ && kubectl apply --wait=true -f cert-manager
	cd kubernetes/ && kubectl apply --wait=true -f letsencrypt
	cd kubernetes/ && kubectl apply --wait=true -f nginx
