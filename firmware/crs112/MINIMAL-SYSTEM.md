# Minimal CRS112 development scope

The user removed switch and PoE support from the immediate firmware requirement
on 2026-11-10. The new target is a **serial-console-only RAM development system**.
The [scope declaration](development-scope.json) is planning metadata, not a kernel
configuration, implemented build target or bootable artifact.

No Linux switch or PoE driver was integrated into this project, so there was no
driver implementation to delete. Historical evidence and candidate-source findings
are retained for provenance. They are not linked into a kernel.

## Included in the reduced goal

- Exact-board MIPS CPU, memory, clocks, interrupts and serial-console support.
- A kernel and minimal initramfs with a local shell and basic diagnostics.
- RouterBOOT-compatible RAM loading, reviewed watchdog/reset handling, and a tested
  return to RouterOS without writing flash.

## Excluded from this development profile

- MUSIC Ethernet/switch drivers, PHY/SFP control and hardware forwarding/offload.
- PoE controller drivers, power controls and PoE firmware updaters.
- IP configuration, SSH/web management, online checks and firmware updates on the board.
- Flash mounting/writes, persistent installation and sysupgrade packaging.

There is no supported networking path in this profile. RouterBOOT's network-loading
capability is separate from networking inside the loaded Linux kernel. Loading an
image over Ethernet would not establish that Ethernet works after the kernel starts.
The current remote-only access cannot replace the planned local serial console.

Omitting PoE drivers does **not** establish that PoE outputs are off, nor that switch
forwarding stops or continues. Existing user evidence includes forced-on ports.
Controller state, bootloader behavior and platform reset side effects remain unknown.
Any later hardware test needs independently powered test hardware, no downstream PoE
loads, local console and recovery access. No power state is changed by this scope edit.

## Source integration required before building

There is still no verified CRS112 r2 kernel target. The reviewed historical MUSIC
platform code is a candidate, not a complete matching board port. A future integration
must review platform initialization as well as module selection: excluding `.ko` files
alone does not exclude built-in drivers or shared reset/register writes. Do not copy
the vendor kernel or invent Kconfig symbols to claim these features are disabled.

Before a RAM build: establish the board/boot ABI and suitable source configuration,
implement the minimal platform and console, supply an initramfs, and establish accepted
RouterBOOT image packaging. Then validate RAM boot and recovery locally. A full flash
partition map is not a requirement for an image that never accesses flash, but it
remains necessary before any future persistent installation. No RAM or flash image is
available now; readiness flags remain false.
