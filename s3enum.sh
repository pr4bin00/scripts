#!/bin/bash

# ---------- COLORS ----------
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
NC="\033[0m"

THREADS=20
input="$1"

if [ -z "$input" ]; then
    echo "Usage: $0 subdomains.txt"
    exit 1
fi

check_bucket() {

    sub="$1"
    url="https://s3.amazonaws.com/$sub"

    response=$(curl -s --max-time 5 "$url")

    # Ignore non-existing buckets
    if echo "$response" | grep -q "NoSuchBucket"; then
        return
    fi

    # Detect valid bucket
    if echo "$response" | grep -qiE "AccessDenied|ListBucketResult|PermanentRedirect|AllAccessDisabled"; then

        access="PRIVATE"
        color=$RED

        if echo "$response" | grep -q "ListBucketResult"; then
            access="LISTABLE"
            color=$GREEN
        elif echo "$response" | grep -q "AccessDenied"; then
            access="PRIVATE"
            color=$RED
        else
            access="PUBLIC"
            color=$YELLOW
        fi

        printf "${BLUE}%-40s${NC} ${GREEN}[VALID S3]${NC} access:${color}[%s]${NC}\n" "$sub" "$access"
    fi
}

export -f check_bucket
export GREEN RED BLUE YELLOW NC

cat "$input" | \
sed -E 's|https?://||; s|/.*||' | \
sort -u | \
xargs -P $THREADS -I {} bash -c 'check_bucket "$1"' _ {}
