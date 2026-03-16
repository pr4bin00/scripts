#!/bin/bash

# ---------- COLORS ----------
RED="\033[0;31m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
ORANGE="\033[0;33m"
NC="\033[0m"

THREADS=10

# ---------- FUNCTION TO CHECK BUCKET ----------
check_bucket() {
    bucket="$1"

    read_status="BLOCKED"
    write_status="BLOCKED"
    delete_status="BLOCKED"
    acl_status="BLOCKED"
    acl_perms=""

    # ---------- READ ----------
    if aws s3 ls "s3://$bucket" --no-sign-request >/dev/null 2>&1; then
        read_status="PUBLIC"
    fi

    # ---------- ACL ----------
    acl_json=$(aws s3api get-bucket-acl --bucket "$bucket" --no-sign-request 2>/dev/null)
    if [ $? -eq 0 ]; then
        acl_status="PUBLIC"

        # Capture all permissions for display
        acl_perms=$(echo "$acl_json" | grep -oP '"Permission": "\K[A-Z_]+' | sort -u | tr '\n' ',' | sed 's/,$//')

        # Detect WRITE/DELETE permissions from ACL, including FULL_CONTROL
        if echo "$acl_json" | grep -q '"Permission": "WRITE"\|"Permission": "FULL_CONTROL"'; then
            write_status="PUBLIC"
        fi
        if echo "$acl_json" | grep -q '"Permission": "DELETE"\|"Permission": "FULL_CONTROL"'; then
            delete_status="PUBLIC"
        fi
    fi

    # ---------- POLICY ----------
    policy_json=$(aws s3api get-bucket-policy --bucket "$bucket" --no-sign-request 2>/dev/null)
    if [ $? -eq 0 ]; then
        # Check for s3:PutObject / s3:DeleteObject for AllUsers (*)
        if echo "$policy_json" | grep -q '"Action": "s3:PutObject"'; then
            write_status="PUBLIC"
        fi
        if echo "$policy_json" | grep -q '"Action": "s3:DeleteObject"'; then
            delete_status="PUBLIC"
        fi
    fi

    # ---------- COLOR MAPPING ----------
    r_color=$RED; [ "$read_status" = "PUBLIC" ] && r_color=$GREEN
    w_color=$RED; [ "$write_status" = "PUBLIC" ] && w_color=$GREEN
    d_color=$RED; [ "$delete_status" = "PUBLIC" ] && d_color=$GREEN
    a_color=$RED; [ "$acl_status" = "PUBLIC" ] && a_color=$GREEN

    # ---------- BUILD OUTPUT ----------
    bucket_output="${BLUE}$bucket${NC}  READ:${r_color}$read_status${NC}  WRITE:${w_color}$write_status${NC}  DELETE:${d_color}$delete_status${NC}  ACL:${a_color}$acl_status${NC}"

    # Append ACL permissions in square brackets if available
    if [ "$acl_perms" != "" ]; then
        bucket_output+=" [${ORANGE}$acl_perms${NC}]"
    fi

    # Add newline before file list if any
    if [ "$read_status" = "PUBLIC" ]; then
        files=$(aws s3 ls "s3://$bucket" --no-sign-request 2>/dev/null | grep -v 'PRE')
        if [ "$files" != "" ]; then
            bucket_output+=$'\n'"$files"
        fi
    fi

    # ---------- PRINT ----------
    echo -e "$bucket_output"$'\n'
}

# ---------- EXPORT FOR xargs ----------
export -f check_bucket
export RED GREEN BLUE NC ORANGE

# ---------- SINGLE BUCKET ----------
if [ "$1" != "" ] && [ ! -f "$1" ]; then
    check_bucket "$1"
fi

# ---------- LIST OF BUCKETS ----------
if [ -f "$1" ]; then
    cat "$1" | xargs -P $THREADS -I {} bash -c 'check_bucket "$@"' _ {}
fi
