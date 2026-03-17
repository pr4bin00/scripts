#!/bin/bash

# ---------- COLORS ----------
RED="\033[0;31m"
GREEN="\033[0;32m"
PARAM_COLOR="\033[0;36m"  # Same color for all parameter names
BLUE="\033[0;34m"
NC="\033[0m"

THREADS=10
OUTPUT_FILE=""

# ---------- ARG PARSE ----------
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -o) OUTPUT_FILE="$2"; shift ;;
        *) INPUT="$1" ;;
    esac
    shift
done

# ---------- CREATE CSV HEADER ----------
if [ "$OUTPUT_FILE" != "" ]; then
    echo "bucket,read,write,delete,acl" > "$OUTPUT_FILE"
fi

# ---------- FUNCTION TO CHECK BUCKET ----------
check_bucket() {
    bucket="$1"

    read_status="BLOCKED"
    write_status="BLOCKED"
    delete_status="BLOCKED"
    acl_status="BLOCKED"

    # ---------- ACL ----------
    acl_json=$(aws s3api get-bucket-acl --bucket "$bucket" --no-sign-request 2>/dev/null)
    if [ $? -eq 0 ] && [ "$acl_json" != "" ]; then
        public_perms=()
        if echo "$acl_json" | grep -q '"Type": "Group"' && echo "$acl_json" | grep -q 'AllUsers\|AuthenticatedUsers'; then
            echo "$acl_json" | grep -q '"Permission": "READ"\|"Permission": "FULL_CONTROL"' && public_perms+=("READ") && read_status="PUBLIC"
            echo "$acl_json" | grep -q '"Permission": "WRITE"\|"Permission": "FULL_CONTROL"' && public_perms+=("WRITE") && write_status="PUBLIC"
            echo "$acl_json" | grep -q '"Permission": "DELETE"\|"Permission": "FULL_CONTROL"' && public_perms+=("DELETE") && delete_status="PUBLIC"
        fi
        if [ ${#public_perms[@]} -gt 0 ]; then
            acl_status="PUBLIC [${public_perms[*]}]"
        fi
    fi

    # ---------- BUCKET POLICY ----------
    policy_json=$(aws s3api get-bucket-policy --bucket "$bucket" --no-sign-request 2>/dev/null)
    if [ $? -eq 0 ] && [ "$policy_json" != "" ]; then
        if echo "$policy_json" | grep -q '"Action": "s3:GetObject"' && echo "$policy_json" | grep -q '"Principal": "\*"' ; then
            read_status="PUBLIC"
        fi
        if echo "$policy_json" | grep -q '"Action": "s3:PutObject"' && echo "$policy_json" | grep -q '"Principal": "\*"' ; then
            write_status="PUBLIC"
        fi
        if echo "$policy_json" | grep -q '"Action": "s3:DeleteObject"' && echo "$policy_json" | grep -q '"Principal": "\*"' ; then
            delete_status="PUBLIC"
        fi
    fi

    # ---------- FALLBACK: aws s3 ls if read still blocked ----------
    object_list=""
    if [ "$read_status" = "BLOCKED" ]; then
        if aws s3 ls "s3://$bucket" --no-sign-request >/dev/null 2>&1; then
            read_status="PUBLIC"
        fi
    fi

    # ---------- LIST OBJECTS IF READ IS PUBLIC ----------
    if [ "$read_status" = "PUBLIC" ]; then
        object_list=$(aws s3 ls "s3://$bucket" --no-sign-request 2>/dev/null | grep -v 'PRE')
    fi

    # ---------- COLORS FOR STATUS ----------
    r_color=$RED; [ "$read_status" = "PUBLIC" ] && r_color=$GREEN
    w_color=$RED; [ "$write_status" = "PUBLIC" ] && w_color=$GREEN
    d_color=$RED; [ "$delete_status" = "PUBLIC" ] && d_color=$GREEN
    a_color=$RED; [ "$acl_status" != "BLOCKED" ] && a_color=$GREEN

    # ---------- TERMINAL OUTPUT (Atomic) ----------
    (
        echo -e "${BLUE}$bucket${NC}  ${PARAM_COLOR}READ${NC}:${r_color}$read_status${NC}  ${PARAM_COLOR}WRITE${NC}:${w_color}$write_status${NC}  ${PARAM_COLOR}DELETE${NC}:${d_color}$delete_status${NC}  ${PARAM_COLOR}ACL${NC}:${a_color}$acl_status${NC}"
        [ "$object_list" != "" ] && echo "$object_list"
    )

    # ---------- CSV OUTPUT ----------
    if [ "$OUTPUT_FILE" != "" ]; then
        (
            flock -x 200
            echo "$bucket,$read_status,$write_status,$delete_status,$acl_status" >> "$OUTPUT_FILE"
        ) 200>/tmp/s3csv.lock
    fi
}

# ---------- EXPORT FOR xargs ----------
export -f check_bucket
export RED GREEN BLUE PARAM_COLOR NC OUTPUT_FILE

# ---------- SINGLE BUCKET ----------
if [ "$INPUT" != "" ] && [ ! -f "$INPUT" ]; then
    check_bucket "$INPUT"
fi

# ---------- LIST OF BUCKETS ----------
if [ -f "$INPUT" ]; then
    cat "$INPUT" | xargs -P $THREADS -I {} bash -c 'check_bucket "$@"' _ {}
fi