#!/bin/bash


# Increase file descriptor limit to prevent knockpy DNS errors

ulimit -n 8192


# Colors

GREEN='\033[0;32m'

NC='\033[0m'


# Check if a domain is provided

if [ -z "$1" ]; then

  echo -e "${GREEN}Usage: $0 <domain>${NC}"

  exit 1

fi


domain=$1


# Create a directory for the domain if it doesn't exist

mkdir -p $domain


# Run subfinder

echo -e "${GREEN}[*] Running subfinder...${NC}"

subfinder -silent -r 8.8.8.8,1.1.1.1 -d $domain -config '/Users/0xpr4bin/Library/Application Support/subfinder/provider-config.yaml' -o $domain/subfinder_${domain}.txt


# Run knockpy

echo -e "${GREEN}[*] Running knockpy...${NC}"

knockpy -d $domain --recon --bruteforce --save /tmp/$domain

cat /tmp/$domain/*.json | sort -u | cut -d '\"' -f4 > $domain/knockpy_${domain}.txt


# Run findomain

echo -e "${GREEN}[*] Running findomain...${NC}"

findomain_virustotal_token="" findomain_securitytrails_token="mumzsVaQaWpalB_heBCKEfWlq1ODylG8" findomain_certspotter_token="k49566_yHCkBJPJ9aJO3JO3nZ6R" findomain_bufferover_free_api_key="z11UHT9Sci8b9NyRMvI6N4P3IVMbrdI27hWJW6cJ" findomain_fullhunt_api_key="62146fa2-0061-4100-9072-3594286733af" findomain -t $domain -u $domain/findomain_${domain}.txt

# findomain -t $domain -u $domain/findomain_${domain}.txt


# Download data from ShrewdEye

echo -e "${GREEN}[*] Fetching data from ShrewdEye...${NC}"

wget -q -O $domain/shrewdeye_${domain}.txt "https://shrewdeye.app/domains/$domain.txt?valid=true"


echo -e "${GREEN}[*] Subdomain enumeration completed. Results saved in the '$domain' directory.${NC}"


# =================================================

# DO NOT TOUCH ABOVE — POST-PROCESSING STARTS HERE

# =================================================


cd $domain || exit 1


echo -e "${GREEN}[*] Merging all subdomains...${NC}"

cat * | sort -u | tee subdomains


echo -e "${GREEN}[*] Cleaning up .txt files...${NC}"

rm *.txt


echo -e "${GREEN}[*] Running httpx...${NC}"

cat subdomains | httpx -sc -td -title -location | tee httpx


echo -e "${GREEN}[*] Extracting live URLs...${NC}"

cat httpx | awk '{print $1}' | tee urls


echo -e "${GREEN}[*] Running nuclei...${NC}"

cat urls | nuclei -t ~/nuclei-templates/ -severity low,medium,high,critical -exclude-tags headers,tls,ssl,sslcert,misconfiguration,info -rate-limit 150 -bulk-size 25 -concurrency 25 -timeout 5 -retries 1 | tee nuclei_output 


echo -e "${GREEN}[✓] Done! Full recon + nuclei scan completed.${NC}"
