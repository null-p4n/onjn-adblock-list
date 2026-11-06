# ONJN Romania Gambling Blocklist

DNS blocklist built from the **ONJN** (Oficiul Național pentru Jocuri de Noroc) blacklist of unlicensed gambling domains, formatted for AdGuard Home, Pi-hole and similar DNS filters.

- **Snapshot date:** 2026-11-06
- **Entries:** 2,920 unique domains
- **Source:** ONJN blacklist, published at [onjn.gov.ro](https://onjn.gov.ro). This repo is a reformatted snapshot, not an official mirror.

## Files

| File | Format |
|---|---|
| `onjn_blocklist.txt` | Blocklist syntax (`\|\|domain^`), blocks the domain and all subdomains |
| `onjn_domains.txt` | Plain domain list, one per line |
| `update.sh` | Updater for Linux/macOS (bash + curl) |
| `update.ps1` | Updater for Windows (PowerShell 5.1 and 7+) |

## Usage

### AdGuard Home

Filters → DNS blocklists → Add a custom list → paste the raw URL (or a local file path):

```
https://raw.githubusercontent.com/null-p4n/onjn-adblock-list/refs/heads/main/onjn_blocklist.txt
```

### Pi-hole

Adlists → add the raw URL of `onjn_domains.txt`, then run `pihole -g`.

### Other resolvers

`onjn_domains.txt` converts easily to other formats:

```bash
# dnsmasq
sed 's|.*|address=/&/0.0.0.0|' onjn_domains.txt > onjn.dnsmasq.conf

# Unbound
sed 's|.*|local-zone: "&" always_null|' onjn_domains.txt > onjn.unbound.conf
```

## Review before enabling

The ONJN list is broad. These entries are likely unwanted for personal use, so remove them if you need them:

- Prediction markets: `kalshi.com`, `polymarket.com`
- Non-gambling or unclear: `immersion.com`, `21.co.uk`, `nike.sk`, `theclan.gg`
- Car and prize raffle sites: `carscor.com`, `ls-cars.com`, `coco-automobile.ro`, `masini-random.ro`
- Large international brands (`bet365.com`, `1xbet.com`, `williamhill.com`, etc.) will be blocked network-wide.
- `vulkan-vegas.accountan` looks like a truncated `.accountant` in the source. The correct entry also exists, so it is harmless.

## Updating

ONJN adds mirrors constantly. The updaters download the official `Lista-neagra.txt`, normalize it (lowercase, strips scheme, path, port and leading `www.`, dedupes, drops invalid names) and rewrite both list files.

```bash
./update.sh                    # Linux/macOS, needs curl
DRY_RUN=1 ./update.sh          # show added/removed domains, write nothing
```

```powershell
.\update.ps1                   # Windows PowerShell 5.1 or PowerShell 7+
.\update.ps1 -DryRun
```

Both scripts:

- fetch over HTTPS only unless you opt in to plain http (`ALLOW_HTTP=1` / `-AllowHttp`)
- refuse to overwrite the lists if fewer than 500 valid domains are parsed, or if the list shrinks by more than 50% (override with `FORCE=1` / `-Force`)
- print the added and removed domains and leave the files untouched when nothing changed
- accept a local copy of the list (`SRC_FILE=Lista-neagra.txt` / `-SourceFile`) for offline use or when the site blocks automated downloads
- write via temp file and rename, so a failed run never leaves a half-written list

Schedule it if you host the list yourself:

```bash
# crontab: weekly, Mondays 04:00
0 4 * * 1  cd /path/to/repo && ./update.sh >> update.log 2>&1
```

```powershell
# Task Scheduler: weekly
$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -File C:\path\to\repo\update.ps1'
$t = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 4am
Register-ScheduledTask -TaskName 'ONJN list update' -Action $a -Trigger $t
```

## License

The list is derived from public ONJN data. Verify against the official source before relying on it.
