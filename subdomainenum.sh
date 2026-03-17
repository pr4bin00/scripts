#!/bin/bash


# Check if a domain is provided

if [ -z "$1" ]; then

  echo "Usage: $0 <domain>"

  exit 1

fi


domain=$1


# Create a directory for the domain if it doesn't exist

mkdir -p $domain


# Run subfinder

echo "[*] Running subfinder..."

subfinder -silent -r 8.8.8.8,1.1.1.1 -d $domain -config '/home/prabinsigdel/.config/subfinder/provider-config.yaml' -o $domain/subfinder_${domain}.txt


# Run knockpy

echo "[*] Running knockpy..."

knockpy -d $domain --recon --bruteforce --save /tmp/$domain

cat /tmp/$domain/*.json | sort -u | cut -d '\"' -f4 > $domain/knockpy_${domain}.txt


# Run findomain

echo "[*] Running findomain..."

findomain_virustotal_token="" findomain_securitytrails_token="mumzsVaQaWpalB_heBCKEfWlq1ODylG8" findomain_certspotter_token="k49566_yHCkBJPJ9aJO3JO3nZ6R" findomain_bufferover_free_api_key="z11UHT9Sci8b9NyRMvI6N4P3IVMbrdI27hWJW6cJ" findomain_fullhunt_api_key="62146fa2-0061-4100-9072-3594286733af" findomain -t $domain -u $domain/findomain_${domain}.txt

# findomain -t $domain -u $domain/findomain_${domain}.txt


# Download data from ShrewdEye

echo "[*] Fetching data from ShrewdEye..."

wget -q -O $domain/shrewdeye_${domain}.txt "https://shrewdeye.app/domains/$domain.txt?valid=true"


echo "[*] Subdomain enumeration completed. Results saved in the '$domain' directory."
