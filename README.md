# ONJN Romania Gambling Blocklist

DNS blocklist built from the **ONJN** (Oficiul Național pentru Jocuri de Noroc) blacklist of unlicensed gambling domains, formatted for AdGuard Home, Pi-hole and similar DNS filters.

- **Snapshot date:** 2026-11-06
- **Entries:** 2,920 unique domains
- **Source:** ONJN blacklist, published at [onjn.gov.ro](https://www.onjn.gov.ro). This repo is a reformatted snapshot, not an official mirror.

## Files

| File | Format |
|---|---|
| `onjn_adguard.txt` | AdGuard syntax (`\|\|domain^`), blocks the domain and all subdomains |
| `onjn_domains.txt` | Plain domain list, one per line |

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

ONJN adds mirrors constantly. To regenerate from a fresh export of the official list:

```bash
tr -d '\r' < Lista-neagra.txt | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr 'A-Z' 'a-z' \
  | grep -E '^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$' | sort -u > onjn_domains.txt
sed 's/.*/||&^/' onjn_domains.txt > onjn_adguard.txt
```

Add AdGuard header lines (`! Title: ...`) at the top of `onjn_adguard.txt` if you want the list to show a name in the UI.

## License

The list is derived from public ONJN data. Verify against the official source before relying on it.
