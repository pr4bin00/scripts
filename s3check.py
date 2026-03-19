#!/usr/bin/env python3
import boto3
from botocore import UNSIGNED
from botocore.client import Config
import concurrent.futures
import argparse
import csv
from datetime import datetime
import os
import subprocess
import queue
import threading
import tempfile

# ---------- COLORS ----------
RED = "\033[0;31m"
GREEN = "\033[0;32m"
PARAM_COLOR = "\033[0;36m"
BLUE = "\033[0;34m"
NC = "\033[0m"

# ---------- ARGUMENTS ----------
parser = argparse.ArgumentParser()
parser.add_argument("input", help="Bucket name or file with bucket list")
parser.add_argument("-o", "--output", help="CSV output file", default="")
parser.add_argument("-t", "--threads", help="Number of parallel threads", type=int, default=20)
args = parser.parse_args()

OUTPUT_FILE = args.output
THREADS = args.threads

# ---------- CSV QUEUE ----------
csv_queue = queue.Queue()
csv_lock = threading.Lock()

def csv_writer():
    while True:
        row = csv_queue.get()
        if row is None:  # Sentinel to exit
            csv_queue.task_done()
            break
        with csv_lock:
            with open(OUTPUT_FILE, "a", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(row)
        csv_queue.task_done()

# ---------- S3 CLIENTS ----------
s3_client = boto3.client("s3", config=Config(signature_version=UNSIGNED))
s3api_client = boto3.client("s3", config=Config(signature_version=UNSIGNED))

# ---------- CHECK BUCKET ----------
def check_bucket(bucket):
    read_methods = []
    write_methods = []
    delete_methods = []
    read_status = "BLOCKED"
    write_status = "BLOCKED"
    delete_status = "BLOCKED"
    acl_status = "BLOCKED"
    object_list = []

    # ---------- ACL ----------
    try:
        acl_json = s3api_client.get_bucket_acl(Bucket=bucket)
        public_perms = []
        for grant in acl_json.get("Grants", []):
            grantee = grant.get("Grantee", {})
            perm = grant.get("Permission", "")
            if grantee.get("Type") == "Group" and ("AllUsers" in grantee.get("URI","") or "AuthenticatedUsers" in grantee.get("URI","")):
                if perm in ["READ","FULL_CONTROL"]:
                    public_perms.append("READ")
                if perm in ["WRITE","FULL_CONTROL"]:
                    public_perms.append("WRITE")
                if perm in ["DELETE","FULL_CONTROL"]:
                    public_perms.append("DELETE")
        if public_perms:
            acl_status = f"PUBLIC [{', '.join(public_perms)}]"
    except Exception:
        acl_status = "BLOCKED"

    # ---------- READ TEST ----------
    try:
        result = subprocess.run(
            ["aws","s3","ls",f"s3://{bucket}","--no-sign-request"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            read_methods.append("s3")
            object_list = [line for line in result.stdout.splitlines() if "PRE" not in line]
    except Exception:
        pass

    try:
        s3api_client.list_objects_v2(Bucket=bucket, MaxKeys=1)
        read_methods.append("s3api")
    except Exception:
        pass

    if read_methods:
        read_status = f"PUBLIC[{','.join(read_methods)}]"

    # ---------- WRITE & DELETE TEST ----------
    temp_key = f"s3scanner_test_{datetime.now().timestamp()}.txt"
    write_ok = False

    # Use a real temporary file for aws s3 cp
    with tempfile.NamedTemporaryFile("w+b", delete=False) as tmp:
        tmp.write(b"s3scanner test")
        tmp.flush()
        tmp_file_path = tmp.name

    # WRITE test s3
    try:
        subprocess.run(
            ["aws","s3","cp",tmp_file_path,f"s3://{bucket}/{temp_key}","--no-sign-request"],
            capture_output=True, text=True, check=True
        )
        write_methods.append("s3")
        write_ok = True
    except Exception:
        pass

    # WRITE test s3api
    try:
        with open(tmp_file_path,"rb") as f:
            s3api_client.put_object(Bucket=bucket, Key=temp_key, Body=f)
        write_methods.append("s3api")
        write_ok = True
    except Exception:
        pass

    if write_methods:
        write_status = f"PUBLIC[{','.join(write_methods)}]"

    # DELETE test if write succeeded
    if write_ok:
        try:
            subprocess.run(
                ["aws","s3","rm",f"s3://{bucket}/{temp_key}","--no-sign-request"],
                capture_output=True, text=True, check=True
            )
            delete_methods.append("s3")
        except Exception:
            pass
        try:
            s3api_client.delete_object(Bucket=bucket, Key=temp_key)
            delete_methods.append("s3api")
        except Exception:
            pass
        if delete_methods:
            delete_status = f"PUBLIC[{','.join(delete_methods)}]"
        else:
            delete_status = "BLOCKED"
    else:
        delete_status = "BLOCKED"

    # Remove temp file
    os.unlink(tmp_file_path)

    # ---------- TERMINAL OUTPUT ----------
    r_color = GREEN if read_status.startswith("PUBLIC") else RED
    w_color = GREEN if write_status.startswith("PUBLIC") else RED
    d_color = GREEN if delete_status.startswith("PUBLIC") else RED
    a_color = GREEN if acl_status!="BLOCKED" else RED

    print(f"{BLUE}{bucket}{NC}  {PARAM_COLOR}READ{NC}:{r_color}{read_status}{NC}  {PARAM_COLOR}WRITE{NC}:{w_color}{write_status}{NC}  {PARAM_COLOR}DELETE{NC}:{d_color}{delete_status}{NC}  {PARAM_COLOR}ACL{NC}:{a_color}{acl_status}{NC}")
    for obj in object_list:
        print(obj)

    # ---------- CSV OUTPUT ----------
    if OUTPUT_FILE:
        csv_queue.put([bucket, read_status, write_status, delete_status, acl_status])

# ---------- BUCKET LIST ----------
buckets = []
if os.path.isfile(args.input):
    with open(args.input) as f:
        buckets = [line.strip() for line in f if line.strip()]
else:
    buckets = [args.input]

# ---------- START CSV WRITER THREAD ----------
if OUTPUT_FILE:
    t = threading.Thread(target=csv_writer, daemon=True)
    t.start()

# ---------- PARALLEL EXECUTION ----------
with concurrent.futures.ThreadPoolExecutor(max_workers=THREADS) as executor:
    futures = [executor.submit(check_bucket, b) for b in buckets]
    concurrent.futures.wait(futures)

# ---------- FINISH CSV WRITER ----------
if OUTPUT_FILE:
    csv_queue.put(None)
    csv_queue.join()