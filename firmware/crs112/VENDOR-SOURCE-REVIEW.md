# Additional MIPS platform source evidence

Reviewed 2026-11-10. The public [RouterOS source mirror](https://github.com/robimarko/routeros-GPL/tree/63164edb5398041b2da4aabdcfe0d0c3fdd00f06)
contains more relevant platform code than the MR53 OpenWrt fork. Its provenance is
a third-party mirror of vendor source, not an authenticated source delivery for this
user's RouterOS 6.48.6. The inspected material includes a tree labeled RouterOS 6.44
and a patch/configuration directory dated 2020-03-20. Neither establishes the exact
source/configuration of the installed version.

## What the files actually contain

At commit `63164edb5398041b2da4aabdcfe0d0c3fdd00f06`, under
`linux_3_3_5_patch_RouterOS644/`:

- `arch/mips/rb/music.c` implements platform startup pieces: CPU frequency selection,
  timer frequency setup, early UART configuration and restart handling.
- `arch/mips/rb/music_irq.c` implements interrupt dispatch and controller operations.
- `arch/mips/rb/prom.c` recognizes boot board strings `ccs112` and `ccs112r4`, assigning
  the MUSIC machine group and different machine types. These are source-level names;
  the user's boot command line has not been captured.
- `arch/mips/rb/platform.c` has a `ccs112_eth_port_map` headed by chip identifier 8511,
  with eight ordinary entries and four flagged entries, and a `music` Ethernet
  platform-device registration. It also defines `ccs112r4` devices with an optional
  `spi-poe-pse` component selected by `HW_OPT_HAS_POE_OUT`.
- That PoE platform data specifies two PSUs and eight channels. This is a useful
  correspondence with the product's port count and supplied health output, **not
  proof that the user's r2 board uses that exact mapping or controller**.
- `drivers/mtd/nand/music_nand.c` is a MUSIC SPI NAND driver with dependencies on
  other RouterBOARD code. It includes shared-control operations affecting PoE reset.
  Its presence does not establish that this 16 MiB board uses that NAND path.

The dated 2020 patch also contains the `ccs112`/`ccs112r4` definitions. The source
manifest records both reviewed versions and hashes rather than assuming they match.

## What this changes

There is now candidate **MIPS platform code**, plus candidate board/PoE integration
metadata, to investigate alongside the MR53 switch-register source. The earlier lack
of an established upstream OpenWrt target remains true; it should not be described
as an absence of all historical vendor platform code.

The internal name `ccs112r4` must not be equated with the RouterOS-reported revision
`r2`, or substituted for it based on naming alone. A boot log, exact-version source
configuration and physical component evidence are still needed to establish that
relationship. No source register address or GPIO assignment has been installed into
this project's board configuration.

## Remaining implementation gaps

Platform-device registration is not the implementation of its driver. This review
has not established complete compatible `music` Ethernet/switch and `spi-poe-pse`
drivers, their firmware/protocol requirements, a modern OpenWrt integration, or safe
PoE startup. The NAND source is not evidence of this board's flash geometry or
bootloader-preserving partition map. Root filesystem construction and accepted
RouterBOOT/sysupgrade packaging remain unfinished.

No source here was built or run. Compiling this historical kernel with guessed
configuration would not validate a CRS112 r2 image. The next concrete evidence is:

1. Ordinary serial boot log showing the board identifier and boot parameters, obtained
   with local recovery access during an authorized maintenance window or on a spare unit.
2. Vendor confirmation of how `ccs112`/`ccs112r4` maps to CRS112-8P-4S r2 and the
   corresponding RouterOS 6.48.6 platform configuration.
3. Matching Ethernet/switch and PoE implementation/protocol evidence, flash geometry,
   bootloader preservation, and RAM-boot image constraints.
4. Exact-board RAM boot and recovery testing before any persistent image design.

The [updated vendor request](vendor-source-request.txt) asks those specific questions.
It is still an unsent draft. See [review manifest](evidence/vendor-source-review.json)
for paths and hashes. Firmware readiness flags remain false.
