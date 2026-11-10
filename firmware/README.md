# Linux firmware research — no installable images

Checked 2026-11-10. These are two independent board workspaces, not firmware releases.
No target, device tree, flash map, PoE driver or flashable image has been invented.
No device was accessed, booted or flashed by this agent. The user subsequently supplied
CRS112 r2 RouterOS/RouterBOOT identity output; it is recorded with identifiers redacted
in the CRS112 workspace. RouterOS remains the supported monitoring platform.

| Workspace | Exact product | Vendor architecture / silicon | Build target |
|---|---|---|---|
| [netpower16p](netpower16p/README.md) | CRS318-16P-2S+OUT | ARM 32-bit / 98DX226S | Unselected: exact-board support unverified |
| [crs112](crs112/README.md) | CRS112-8P-4S-IN | big-endian MIPS / QCA8511 | Unselected: exact-board support unverified |

## Upstream investigation

The [OpenWrt source tree](https://github.com/openwrt/openwrt) was inspected at
`3d5a743f1f0cb77aed8ed63b2f9aa75700b4322c`. Its complete recursive filename index
had no CRS318, CRS112, netPower, 98DX226 or QCA8511 name matches. The
[mvebu image definitions](https://github.com/openwrt/openwrt/blob/3d5a743f1f0cb77aed8ed63b2f9aa75700b4322c/target/linux/mvebu/image/cortexa9.mk)
and [ath79 MikroTik definitions](https://github.com/openwrt/openwrt/blob/3d5a743f1f0cb77aed8ed63b2f9aa75700b4322c/target/linux/ath79/image/mikrotik.mk)
do not establish a target for these exact boards. This is a scoped support investigation,
not proof that no experimental downstream port exists.

A follow-up full-text search of all tracked OpenWrt text files at that commit also
found no matches for those board/chip identifiers or QCA8513. It excludes downloaded
kernel sources and external feeds. The [CRS112 source review](crs112/OPENWRT-RESEARCH.md)
does identify an experimental QCA8511 driver in a Meraki MR53 fork. Source revisions,
hashes and limitations are recorded; no MR53 code or firmware has been substituted
for either requested board.

The subsequent [CRS112 vendor-source review](crs112/VENDOR-SOURCE-REVIEW.md) identifies
historical MUSIC MIPS startup/interrupt code and `ccs112r4` PoE platform metadata in
a pinned third-party RouterOS source mirror. It improves candidate source coverage;
the internal board identifier, driver completeness and mapping to this physical r2
board remain unverified. No build target was selected from these names alone.

The [upstream Linux tree](https://github.com/torvalds/linux) was inspected at
`b3dfbde62cf1981c4638939c159dfd087b7a72e9`. The root recursive index was truncated;
a separate **complete** architecture subtree was then checked. No exact-board or
exact-silicon filename matches were found. Related upstream DTS files for CRS305,
CRS326 and CRS328, and 98DX3236 family support, **are not interchangeable** with either
requested product. In particular, a similarly named CRS318-1Fi-15Fr is not netPower 16P.

Linux has a [Prestera driver](https://github.com/torvalds/linux/tree/b3dfbde62cf1981c4638939c159dfd087b7a72e9/drivers/net/ethernet/marvell/prestera)
and [devlink documentation](https://docs.kernel.org/networking/devlink/prestera.html).
That does not establish the 98DX226S CPU/ASIC integration, transport, required switch
firmware, board wiring, SFP operation, or offload on netPower 16P. No evidence here
establishes a QCA8511 board port or a safe PoE driver for CRS112.

See [upstream-audit.json](upstream-audit.json) for source revisions, URLs, truncation
status, full-text audit scope and related paths. Searches cannot establish complete driver support;
a verified port requires code review and hardware tests.

## Evidence needed next — for each physical board separately

1. Product sticker, PCB revision and clear board/component markings. Record the exact
   SoC, flash, RAM, PHY, PoE controller, voltage rails and board revision without
   assuming that vendor marketing names identify a register-compatible chip.
2. Read-only RouterOS output: `/system resource print`, `/system routerboard print`,
   `/system routerboard settings print`, `/interface ethernet print detail`,
   `/interface ethernet switch print`, `/system health print`; installed packages and
   RouterOS version. Remove serials, MACs, addresses, comments and secrets before sharing.
3. Cold-boot serial log, RouterBOOT current/factory versions, boot menu, supported
   network boot modes, image format/signature restrictions, protected-routerboot status
   and verified console electrical levels/pinout for this revision. Do not guess pins.
4. Authoritative flash geometry, erase size, partition map and read-only dump plan.
   Identify primary/backup RouterBOOT, board data, calibration, MACs, license and any
   recovery partitions. Obtain independently verified backups and hashes before any
   future persistent work. RouterOS configuration exports alone are insufficient.
5. Datasheets or reviewed upstream bindings for CPU, clocks, interrupts, RAM init,
   console, PHY/MDIO, switch CPU port, front-panel port map, SFP I²C/LOS/TX-disable,
   reset lines, GPIO, watchdog and temperature sensors.
6. PoE controller identification, bus/protocol, voltage selection, detection, current
   limit, thermal protection and power-on/reset behavior. Validate safe defaults with
   downstream loads disconnected. Forced PoE must never be enabled automatically.
7. Local hardware access with serial console, isolated management Ethernet, a stable
   power supply, known-good official recovery media, and a tested RouterOS recovery
   procedure. Vendor Netinstall capability is not proof that a custom Linux image boots.

The optional `python -m airlink.evidence --device ID --output FILE.json` collector
uses the configured backend's verified SSH connection for read-only evidence, creates
a new private file, and redacts common serial/MAC/comment fields. Review the complete
file before sharing. It cannot discover a flash layout or PCB wiring from RouterOS.

## Gated RAM-boot workflow (not yet runnable)

1. Complete identity, console and RouterBOOT evidence above; obtain an exact-board
   upstream port or review a documented new port. Pin source commits and toolchain.
2. Establish the board's accepted RAM-boot protocol and image packaging from evidence.
   Do not change RouterBOOT settings as part of this project. No boot address is supplied.
3. Build an **exact-board** kernel plus a minimal initramfs root filesystem with a shell,
   console and diagnostics. Do not include automatic partition mounting or flash writers.
   Keep writable flash drivers disabled until their map and preservation rules are reviewed.
4. In a separately authorized hardware session, use an isolated network and verified
   one-time RAM boot, with serial recovery available and PoE loads disconnected.
5. Verify console, RAM, timers, Ethernet management, every copper/fiber interface, watchdog,
   temperature and reboot-to-RouterOS recovery. Then validate switch forwarding/offload and
   safe PoE control independently. A booting kernel does not imply a working switch.
6. Only after RAM-boot tests pass can filesystem size/overlay, persistent image headers,
   checksums/signatures, partition alignment, bootloader preservation and rollback be designed.
   Persistent installation is outside the present task and has not been implemented.

**Unfinished for both boards:** exact board support/DTS, switch and PoE drivers,
flash layout, root filesystem/image packaging, watchdog/sensor validation and tested recovery.
