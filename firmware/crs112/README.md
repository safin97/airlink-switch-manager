# CRS112-8P-4S-IN

**Research workspace only. No selected build target or bootable image.**

**Current scope:** [minimal serial-console RAM development](MINIMAL-SYSTEM.md),
with switch, Ethernet/SFP and PoE drivers excluded at the user's request. These
features are no longer prerequisites for this reduced milestone. There is no
supported remote networking or online updating in the planned minimal system.
The inventory below preserves the broader hardware research; it is not a list of
features implemented or required for the reduced profile.

The requested RouterOS identity, switch, interface, health and package inventory is now
complete from user-supplied output. Minimal platform source/configuration, RAM image
packaging and recovery evidence remain incomplete; see [BRINGUP.md](BRINGUP.md).

The expanded [OpenWrt source review](OPENWRT-RESEARCH.md) identifies experimental
QCA8511 code in a Meraki MR53 fork, with pinned commits and file hashes. It is a
driver research candidate; CRS112 compatibility and a build target remain unverified.

A further [vendor-source review](VENDOR-SOURCE-REVIEW.md) identifies historical MIPS
MUSIC startup/interrupt code and `ccs112r4` PoE platform metadata. The internal board
identifier is not yet mapped to this physical r2 board; this is research evidence,
not an implemented board port.

MikroTik's [product specification](https://mikrotik.com/product/crs112_8p_4s_in) lists
MIPSBE (big-endian MIPS), QCA8511 CPU/switch, one 400 MHz core, 128 MB RAM,
16 MB flash, eight Gigabit Ethernet PoE-out ports and four 1G SFP ports.
Do not infer QCA8511 compatibility from a different Qualcomm/Atheros SoC.

The [model manual](https://help.mikrotik.com/docs/spaces/UM/pages/17498209/CRS112-8P-4S-IN)
describes the RJ45 serial console, 115200 8N1, backup RouterBOOT and Netinstall on
Ethernet 1. That is recovery documentation, not validation of a custom RAM-boot image.
User-supplied CLI evidence now reports revision **r2**, RouterBOOT **6.48.6**, firmware
type **qca8513L**, and protected-routerboot **disabled**. See the
[recorded evidence](evidence/routeros-6.48.6-r2-user-report.json) and
[bring-up assessment](BRINGUP.md). These were not independently read over SSH.

| Component | Evidence/status |
|---|---|
| PCB revision / boot behavior | RouterOS reports r2 / RouterBOOT 6.48.6; physical markings and serial boot log still missing |
| MIPS CPU / DTS | Exact CPU integration, interrupt/clock support and board DTS unverified |
| Flash | 16 MB capacity only; geometry, partition layout, bootloader preservation unfinished |
| Ethernet / ASIC | RouterOS reports QCA-8511; user output confirms ether1–ether8 and sfp9–sfp12; Linux driver, CPU port and offload support unverified |
| SFP | PHY/SerDes, I²C and module control mapping unfinished |
| PoE | Controller identification, bus protocol, rail selection and safe driver unfinished |
| Root filesystem / image | MIPSBE userspace, initramfs and accepted RouterBOOT packaging not built |
| Watchdog / sensors | RouterOS reports temperature and two PSU voltages; sensor hardware, Linux integration and watchdog remain unverified |
| Recovery | Model manual available; actual hardware recovery/RAM boot not tested |

Do not substitute a CRS112-8G-4S, CRS109, RB2011 or another ath79 image. No evidence
establishes an ath79 target merely from the MIPSBE architecture. Follow the evidence
list and RAM-boot gates in [../README.md](../README.md). Place reviewed, redacted
board evidence in `evidence/` with revision, date, source and hashes.
