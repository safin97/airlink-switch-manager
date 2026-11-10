# CRS112 r2: assessment after user-provided identity evidence

Updated 2026-11-10. Target: CRS112-8P-4S-IN, reported model CRS112-8P-4S, revision r2.
Source: [redacted CLI evidence](evidence/routeros-6.48.6-r2-user-report.json).
The user supplied this output; no direct connection, reboot or hardware test took place.
The capture timestamp is unknown; the received date is recorded separately.
The user confirmed **remote access only**, with no local serial-console access available.
Keep subsequent collection read-only; hardware boot testing must wait for local recovery access.

## Current reduced milestone

The user subsequently excluded switch and PoE drivers. The active goal is now
[serial-console-only RAM development](MINIMAL-SYSTEM.md), recorded in
[development-scope.json](development-scope.json). Ethernet/SFP, forwarding/offload,
PoE control and online management are excluded. Driver research below is retained
as historical evidence, not a requirement to finish those features before a console
RAM test. No Linux driver had been integrated or removed from a compiled kernel.

## Later boot-setting report

A later user paste on 2026-11-10 reports the same CRS112-8P-4S r2, firmware type
qca8513L, factory RouterBOOT 6.47.10 and current/upgrade RouterBOOT 6.48.6. The changed
field is `boot-device=try-ethernet-once-then-nand`; the earlier report below used
`nand-if-fail-then-ethernet`. Both reports are preserved. See the
[redacted later report](evidence/routerboard-one-time-etherboot-user-report.json).
Neither the capture time nor the person/process that changed the setting was independently
observed. No boot attempt, serial log or successful Linux execution was supplied.

MikroTik's [setting reference](https://manual.mikrotik.com/docs/cli-reference/system/routerboard/settings/)
describes a one-time Etherboot attempt, with internal-storage boot when no server is
available. This documents the setting's intended behavior, not a tested result on this
specific board. It does not identify an acceptable custom image or prove RAM boot,
flash layout, driver operation or recovery. No reboot/settings command was executed
by this project, and all firmware/hardware-readiness flags remain false.

## What the report establishes

- RouterOS 6.48.6 long-term and current RouterBOOT 6.48.6.
- RouterBOARD revision string r2; PCB markings have not yet been inspected.
- CPU reports MIPS 24Kc V8.5, one core at 400 MHz, architecture mipsbe.
- Reported RAM 128.0 MiB and storage capacity 16.0 MiB; free storage 3108.0 KiB.
- Firmware type qca8513L. This is a RouterBOOT family label, **not sufficient evidence
  to replace the product's vendor-listed QCA8511 with a different silicon model**.
- A subsequent `/interface ethernet switch print` reports `switch1` with type
  **QCA-8511**; [selected evidence](evidence/switch-qca8511-user-report.json) is recorded.
  This corroborates the vendor-listed switch type while remaining distinct from
  the `qca8513L` bootloader label. It does not establish a Linux driver or register map.
- The [interface inventory](evidence/ethernet-inventory-r2-user-report.json) contains
  **ether1–ether8** and **sfp9–sfp12**, all assigned to `switch1`. Copper rows have
  `RS` flags (running/slave); all four SFP rows have `X` (disabled) at capture.
  These are user-supplied point-in-time observations, not current live readings.
- Existing PoE configuration: ether1–ether6 `forced-on`, ether7 `off`, ether8 `auto-on`.
  Ether5 selects `low`; the others select `auto`. No configuration was changed.
  These modes do not establish actual delivered voltage/current/power or controller
  reset defaults and must not be copied into an automatic Linux initialization routine.
- Printed `speed=1Gbps` and `full-duplex=yes` are configuration, not confirmed
  negotiation. SFP `sfp-shutdown-temperature=95C` is a threshold, not a sensor reading.
- User-supplied [health output](evidence/health-r2-user-report.json) reports
  `temperature: 39C`, `psu1-voltage: 27.1V`, `psu2-voltage: 0V`. Preserve the zero
  as a reported value, not missing data. These are snapshot readings; their capture
  time is unknown. PSU input readings do not establish per-port PoE output values,
  sensor-controller identity, bus addresses or a Linux sensor driver. Human-readable
  CLI units do not independently verify the SSH `as-value` representation.
- The [package list](evidence/packages-6.48.6-user-report.json) contains 11 entries,
  all version **6.48.6**: routeros-mipsbe, system, ipv6, wireless, hotspot, mpls,
  routing, ppp, dhcp, security and advanced-tools. Only ipv6 is flagged disabled;
  no scheduled actions are shown. Installed `wireless` does not prove a radio exists
  on this board. Package version 6.48.6 is not the underlying Linux kernel version.
- BOOTP configured; boot device nand-if-fail-then-ethernet; serial speed 115200;
  setup entry any-key, boot delay 2 seconds, silent boot off, protected-routerboot disabled.

The CPU core name does not establish the SoC memory map, interrupts, clocks or driver
compatibility. Neither the `nand` word in a boot setting nor the storage capacity proves
flash type, erase geometry, partition offsets or the accepted executable format.
Free RouterOS storage is not a safe Linux installation partition or image-size limit.
The factory-software and factory-firmware fields refer to distinct software components.

## Current conclusion

Identity evidence is improved; an exact-board Linux/OpenWrt build target remains
unverified. The existing upstream audit and follow-up searches did not establish a
CRS112-8P-4S r2 target or a QCA8511/qca8513L driver/board combination. No image was built
or published. A generic MIPS 24Kc kernel cannot be labeled installable for this switch.

An expanded [OpenWrt source review](OPENWRT-RESEARCH.md) now identifies QCA8511
register definitions and driver routines in an experimental Meraki MR53 fork.
These improve the available source evidence, but the different host architecture,
active switch initialization and unverified CRS112 wiring prevent treating the
candidate as a supported CRS112 driver. Official OpenWrt was also searched in full
at the recorded commit, beyond the earlier filename audit.

The subsequent [vendor-source review](VENDOR-SOURCE-REVIEW.md) finds historical MUSIC
MIPS platform code and `ccs112`/`ccs112r4` registrations, including an eight-channel,
two-PSU PoE option. Matching that internal identifier to the reported physical r2
board and locating compatible driver implementations remain unverified.

MikroTik's [RouterBOOT documentation](https://manual.mikrotik.com/docs/getting-started/installation-and-upgrade/routerboot/)
describes network-boot and serial setup capabilities in general. It is not a tested boot
recipe for this r2 board and RouterBOOT 6.48.6. Its example addresses and boot menus must
not be copied as exact-board evidence.

[Netinstall](https://manual.mikrotik.com/docs/getting-started/installation-and-upgrade/netinstall/)
is RouterOS reinstallation and reformats the system drive. It must not be treated as a
non-destructive Linux RAM-boot test. No Netinstall or boot-setting command has been run.

## Requested RouterOS inventory complete — remaining engineering work

All seven requested read-only command groups have been supplied. The project contains
normalized evidence with capture provenance and no unnecessary network identifiers.
No additional generic `print` command is currently required. This completes the requested
CLI inventory, not the board bring-up evidence or live SSH collector validation.

The next independent source task is obtaining and reviewing the exact-board kernel
source/configuration and hardware documentation. A vendor-source request is drafted below;
it has not been sent. No compatible target, source release, image format, flash map or
safe PoE-driver implementation has been established by the package list.

Local serial-console access is currently unavailable and must be arranged before a boot test. A boot log should
be captured during a planned maintenance window or on a spare unit, not by interrupting
this currently running switch. Use the model's documented RJ45 console arrangement and
verify the adapter/pinout; no guessed GPIO/TTL pins. Record an ordinary boot first, with
no setup changes, reset-button actions, storage format, repartition or firmware upgrade.

For the reduced serial-console RAM milestone, the remaining engineering evidence is:

1. Physical revision/component markings and cold-boot serial log.
2. Exact-board source/configuration for CPU, memory, interrupts, clocks and serial UART.
3. Reviewed platform reset/watchdog behavior, including shared peripheral side effects;
   no assumption that omitted drivers turn PoE outputs off.
4. Verified RouterBOOT image format/entry constraints and a minimal initramfs RAM build.
5. Local console, RAM-boot validation and tested return to RouterOS without flash access.

Switch/SFP/offload and PoE implementation are outside this milestone. Flash geometry,
partition layout and bootloader/board-data preservation remain necessary for a future
persistent installation, which is also excluded from this profile.

A [vendor-source request draft](vendor-source-request.txt) is included locally and has
**not been sent**. MikroTik lists a source-request contact in its
[software license/source offer](https://mikrotik.com/software/legal). The draft asks for
this installed version's source and supporting board information, without assuming that
all vendor drivers or documentation are publicly available.

No RAM image is available until the reduced board support and image packaging are
implemented. A verified RAM release still requires local boot/recovery testing.
No persistent image can be released without the additional flash-layout and preservation
work. The intended first hardware test remains an exact-board RAM boot without flash writes.
