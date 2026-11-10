# OpenWrt source findings for CRS112 r2

Checked 2026-11-10. This expands the earlier filename-only audit with a full-text
search and review of an experimental downstream driver. It establishes a useful
**QCA8511 source candidate**, not a build target for CRS112-8P-4S-IN.

## Official OpenWrt

The official [OpenWrt repository](https://github.com/openwrt/openwrt/tree/3d5a743f1f0cb77aed8ed63b2f9aa75700b4322c)
was downloaded and its tracked text files searched at commit
`3d5a743f1f0cb77aed8ed63b2f9aa75700b4322c`:

```sh
git grep -n -i -I -E 'crs112|crs318|qca.?8511|qca.?8513|98dx226|netpower' HEAD --
```

Result: no matches (exit status 1). This covers the checked-in OpenWrt files,
including target definitions and kernel patches. It does not search downloaded
kernel tarballs, external feeds, all historical branches or every downstream fork.
It is not proof that no unpublished port exists. Neither requested board gains a
verified official target from this audit.

## New source candidate: Meraki MR53 downstream port

The original developer's [MR53 project](https://github.com/slow-boat/meraki-mr53/tree/85e4632717fb12d12805c3e1e52da13423884e00)
links an OpenWrt fork containing a QCA8511 driver. The project describes an
IPQ8068 host connected to the switch using QSGMII, with external Ethernet PHYs.
That is a different board architecture from the user's MIPS 24Kc CRS112.

The fork's `mr53` branch was inspected at
`709a91aaefec7f8c7d4520fe32337a218e0525a6`. This is **different from** the wrapper
project's OpenWrt submodule pin, `8780aadc973420d1e61d1b3b6f11bea61ccc81ac`.
The findings below concern the inspected branch revision, not a reproduced release.

| Source inspected | Useful evidence | Limit for CRS112 |
|---|---|---|
| [qca-85xx-sw.c](https://github.com/slow-boat/openwrt/blob/709a91aaefec7f8c7d4520fe32337a218e0525a6/package/kernel/qca85xx-sw/src/qca-85xx-sw.c) | QCA8511 selection, MDIO register transactions, MIB counters, VLAN and port-isolation routines | Requires an existing host MDIO/Ethernet implementation and board configuration; does not supply the CRS112 CPU platform |
| [qca_85xx_sw_regdef.h](https://github.com/slow-boat/openwrt/blob/709a91aaefec7f8c7d4520fe32337a218e0525a6/package/kernel/qca85xx-sw/src/qca_85xx_sw_regdef.h) | Register and bit definitions for the driver's switch operations | Source-level candidate definitions; not independently validated against the CRS112 r2 silicon |
| [qca_85xx_sw.h](https://github.com/slow-boat/openwrt/blob/709a91aaefec7f8c7d4520fe32337a218e0525a6/package/kernel/qca85xx-sw/src/qca_85xx_sw.h) | Chip IDs and port-mode/platform structures | Listed family IDs do not establish support for all family members or front-panel port wiring |
| [MR53 DTS](https://github.com/slow-boat/openwrt/blob/709a91aaefec7f8c7d4520fe32337a218e0525a6/target/linux/ipq806x/dts/qcom-ipq8068-mr53.dts) | Concrete example of driver properties and MDIO/GMAC dependencies | ARM/IPQ8068 board wiring, isolation groups and storage layout must not be transplanted |

Review observations:

- `qca_85xx_sw_probe()` invokes hardware initialization; `qca8511_hw_init()` resets
  the switch and writes its configuration. Loading this module is an active hardware
  operation, not a read-only diagnostic for the remotely managed switch.
- The driver contains the older `switch_dev` interface. `register_switch()` is
  guarded by `MERAKI_REMOVED`; the inspected repository contains no definition of
  that macro. The source therefore does not demonstrate a complete usable CRS112
  VLAN/offload control interface. Its counters and VLAN routines alone prove no
  runtime behavior on this board.
- The source header carries a Linux Foundation permissive notice, the module
  declares GPL, and the package Makefile carries a GPLv2 notice. Preserve notices
  and review provenance before incorporating code. This project records references
  and hashes; it has not imported or modified this driver.

## Historical MikroTik lead

In the [OpenWrt CRS125 development thread](https://forum.archive.openwrt.org/viewtopic.php?id=48706),
the original developer reported basic networking progress in January 2015, with
persistent installation unresolved. That board used an AR9344 host and QCA8513
switch. This is historical development evidence, not CRS112 support or a source
for this board's flash map. The archived thread also reports limits on sharing
the switch configuration code.

The current MR53 forum thread could not be retrieved during this check. The
OpenWrt CRS125 wiki returned an access-denied page. Neither page's unavailable
contents were used to establish support; accessible original source code and the
archived development report were used instead.

## Engineering consequence

There is now concrete switch code to compare with exact-board documentation.
The next source task is establishing the CRS112 CPU/interrupt/clock/MDIO platform,
then checking whether this candidate's access protocol and register definitions
apply. RouterBOOT's `qca8513L` family label does not by itself settle compatibility.

Still unfinished: CRS112 r2 board support/DTS, management Ethernet and all copper/SFP
mapping, switch forwarding/offload integration, PoE controller/driver and safe reset
behavior, flash layout and bootloader preservation, root filesystem/image packaging,
watchdog/sensors, and tested recovery. The candidate supplies no verified solution
for these CRS112-specific requirements. netPower 16P remains a separate ARM workspace.

No downloaded build/flash script was executed; no kernel was compiled, no image
published, and no device settings changed. Remote-only access still prevents a
recoverable hardware boot test. The first hardware test remains a reviewed exact-board
RAM boot with local console/recovery available, followed by reboot-to-RouterOS verification.

See [source manifest](evidence/openwrt-source-review.json) for commits, file hashes
and audit scope, and [BRINGUP.md](BRINGUP.md) for the completed RouterOS inventory.
