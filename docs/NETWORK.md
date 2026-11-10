# Network section: DHCP and static IPv4

Open **Network** in the dashboard. This section prepares management-network settings
for future AirLink firmware. No device-side network service or RouterOS IP write API
is implemented. **Apply to device** is disabled. Current IP and DHCP state are shown
as unavailable; the backend connection URL is not treated as the switch IP.

1. Choose **DHCP** to request automatic address, gateway and DNS assignment, or
   **Static IPv4** to enter fixed settings.
2. Enter the intended management bridge/VLAN interface name. Interface discovery and
   verification are unfinished; no Ethernet port is silently selected for management.
3. In static mode, enter an IPv4 address and subnet prefix, such as `24` for
   `255.255.255.0`. Gateway and up to three comma-separated IPv4 DNS servers are optional.
   A blank gateway means no default route; blank DNS means no configured resolver.
4. Choose **Validate & save draft**. This stores metadata locally in the app/browser,
   scoped to backend origin, device profile ID and product. Demo drafts have their own
   scope. No secrets are stored and no request is sent to the backend or switch.
   The saved JSON is selectable for copying. Reopening the section restores the draft.
5. Changing a field clears the saved-status indication until the new values validate
   and save. Invalid drafts do not overwrite the previously saved valid draft.

The initial DHCP selection is an editor default, not a report of the device's state.
Switching to DHCP omits hidden static fields from the saved draft. Local drafts can be
lost if application/browser storage is cleared and are not encrypted configuration backups.

Validation checks decimal IPv4 syntax, rejects unspecified/loopback/multicast ranges,
and rejects subnet network/broadcast host addresses. This editor supports LAN prefixes
`/1`–`/30`; point-to-point `/31`, host-route `/32`, IPv6, off-subnet gateways and custom
DHCP DNS overrides are not implemented. A gateway must be a different usable address
in the same subnet. DNS entries must be distinct. These are draft-editor constraints,
not a claim that every excluded configuration is invalid networking.

Validation does not detect address conflicts, confirm VLAN membership, reach a DHCP
server, test routes/DNS or verify that the entered interface exists. An eventual IP
change can disconnect remote management. Before enabling live application, implement
authenticated operator permissions, fresh identity/interface/current-configuration
checks, explicit confirmation, atomic device-side changes, a timed rollback unless
connectivity is confirmed, and tested reconnection/recovery. Do not reuse the PoE
permission to authorize network changes. None of these device-side operations exists yet.

The draft is JSON with schema `airlink.network-draft.v1`, `mode` (`dhcp` or `static`),
and `interface`. Static drafts also contain `address`, integer `prefix`, `gateway`
(empty if omitted), and `dns` (a list). This is not a RouterOS script or an installable
configuration file.

Protocol references: [DHCP, RFC 2131](https://www.rfc-editor.org/rfc/rfc2131) and
[CIDR prefix notation, RFC 4632](https://www.rfc-editor.org/rfc/rfc4632).
