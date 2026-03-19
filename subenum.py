#!/usr/bin/env python3

import os
import sys
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor


# ---------------- COLORS ----------------
class C:
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    RESET = "\033[0m"
    BOLD = "\033[1m"


# ---------------- HELP ----------------
def print_help():
    print(f"""
{C.BOLD}Subdomain Enumeration Tool  Version V 2.0 {C.RESET}

USAGE:
    python3 subenum.py <domain>

OPTIONS:
    -h, --help

TOOLS USED:
    - subfinder
    - findomain

OUTPUT:
    <domain>/
        ├── subfinder_<domain>.txt
        ├── findomain_<domain>.txt
""")


# ---------------- CHECK TOOL ----------------
def check_tool(name):
    return shutil.which(name) is not None


# ---------------- RUN COMMAND ----------------
def run_cmd(cmd, name, use_shell=False):
    print(f"{C.YELLOW}[*] Starting {name}...{C.RESET}")

    try:
        subprocess.run(cmd, shell=use_shell, check=True)
        print(f"{C.GREEN}[+] {name} completed{C.RESET}")
    except subprocess.CalledProcessError as e:
        print(f"{C.RED}[-] {name} failed: {e}{C.RESET}")
    except FileNotFoundError:
        print(f"{C.RED}[-] {name} not found in PATH{C.RESET}")


# ---------------- SUBFINDER ----------------
def run_subfinder(domain, outdir):
    if not check_tool("subfinder"):
        print(f"{C.RED}[-] subfinder not found in PATH{C.RESET}")
        return

    cmd = [
        "subfinder",
        "-silent",
        "-r", "8.8.8.8,1.1.1.1",
        "-d", domain,
        "-config", "/home/prabinsigdel/.config/subfinder/provider-config.yaml",
        "-o", f"{outdir}/subfinder_{domain}.txt"
    ]

    run_cmd(cmd, "subfinder", use_shell=False)


# ---------------- FINDOMAIN ----------------
def run_findomain(domain, outdir):
    if not check_tool("findomain"):
        print(f"{C.RED}[-] findomain not found in PATH{C.RESET}")
        print(f"{C.YELLOW}[!] Install: cargo install findomain OR download binary{C.RESET}")
        return

    cmd = (
        f'findomain_virustotal_token="" '
        f'findomain_securitytrails_token="YOUR_TOKEN" '
        f'findomain_certspotter_token="YOUR_TOKEN" '
        f'findomain_bufferover_free_api_key="YOUR_KEY" '
        f'findomain_fullhunt_api_key="YOUR_KEY" '
        f'findomain -t {domain} -u {outdir}/findomain_{domain}.txt'
    )

    run_cmd(cmd, "findomain", use_shell=True)


# ---------------- MAIN ----------------
def main():
    if len(sys.argv) < 2 or sys.argv[1] in ["-h", "--help"]:
        print_help()
        sys.exit(0)

    domain = sys.argv[1]
    outdir = domain

    os.makedirs(outdir, exist_ok=True)

    print(f"\n{C.BLUE}[+] Target: {domain}{C.RESET}")
    print(f"{C.BLUE}[+] Output: {outdir}\n{C.RESET}")

    tasks = [
        run_subfinder,
        run_findomain
    ]

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(task, domain, outdir) for task in tasks]
        for f in futures:
            f.result()

    print(f"\n{C.GREEN}[✓] Completed. Results saved in {outdir}/{C.RESET}")


if __name__ == "__main__":
    main()
