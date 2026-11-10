# Uploaded RouterOS package inspection

Reviewed 2026-11-10. The uploaded `routeros-mipsbe-6.49.19.npk` supplies useful
**compiled kernel and driver evidence**, not a buildable AirLink board target.
It is separate from the user's last reported installed RouterOS 6.48.6.

## Provenance and inspection

The 12,395,478-byte file has SHA-256
`d5f89a4700696785feb41b1a9b810796e4def1172f80a07e59bac11208491d53`.
A separate download from [MikroTik's HTTPS package endpoint](https://download.mikrotik.com/routeros/6.49.19/routeros-mipsbe-6.49.19.npk)
was byte-identical. This comparison is not cryptographic validation of the internal
vendor signatures. The package contains internal January 2026 timestamps, whereas
the [vendor changelog](https://mikrotik.com/download/changelogs?versionFilter=6.49)
lists 6.49.19 under July 2025. Both observations are retained; no conclusion about
rebuild history or authenticity beyond the download comparison is drawn.

The bounded inspector parsed 82 NPK records to exact EOF. Selected files were read
using Debian `unsquashfs` 4.6.1 and `readelf` 2.44 in an unprivileged container with
network disabled, read-only root and read-only input. Nothing from the package was
executed, loaded as a module, uploaded to a switch or included in a public release.
Vendor binaries are kept outside the project. The public evidence contains hashes,
format observations, filenames and short identifying strings only.

## Findings

| Component | Observation | Limit |
| --- | --- | --- |
| `boot/kernel` | 1,314,376-byte ELF32 big-endian MIPS executable; embedded compressed kernel reports Linux 3.3.5 and GCC 4.8.2 | Vendor executable, not an AirLink build or verified RAM-boot image |
| Kernel platform strings | `ccs112`, `ccs112r4`, `MUSIC-IRQ`, `music-spi-nand`, `spi-poe-pse` | Does not map physical revision r2 to an internal board identifier |
| Kernel ELF entry | `0x80400000` | Executable address, **not a flash offset or permission to boot it** |
| Embedded initramfs | XZ-compressed CPIO with `dev`, `dev/ram0`, `dev/console`, `init`, `order` | Vendor bootstrap content; not an independently working AirLink root filesystem |
| Main filesystem | SquashFS 4.0, XZ, 996 inodes; 268 `.ko` paths | RouterOS filesystem packaging does not establish a safe replacement image layout |
| MUSIC modules | `music_gmac.ko`, `music_support.ko`, `music_switch.ko`, `music_dog.ko`; switch module contains `8511` | Compiled implementations exist in this package; compatible rebuildable sources remain unverified |
| PoE modules | `poe_simple.ko`, `poe_v2.ko`, `poe_v3.ko`, `poe_v4.ko`, `poeupdate.ko`; v3 and v4 contain `spi-poe-pse` | Neither identifies the correct r2 driver or proves safe voltage/reset behavior |
| Bootloader-family file | `etc/qca8513L-6.49.19.fwf`, 42,880 bytes, contains `ccs112` | Filename matches the reported firmware family; not a partition map, replacement kernel or tested recovery image |

The inspected modules report `3.3.5 mod_unload MIPS32_R2 32BIT` vermagic. That is
evidence of their expected kernel ABI, not compatibility with a modern kernel.
Although their ELF `depends=` strings are empty, `modules.dep.system` explicitly
lists `music_switch` dependencies on `flash`, `switch`, `phy_amcc_qt2025` and
`phy_helper`, and `music_gmac` dependencies on `switch` and `packet_hook`.
Copying only the MUSIC modules into another kernel would not satisfy those dependencies.

No `.c`, `.h`, `.dts`, `.dtsi`, `.dtb` or `.config` filenames were found in the
filesystem listing. No `IKCFG_ST` marker was found in the two decoded kernel XZ
streams. These are scoped search results, not proof that all build information is
absent from every possible encoding. Full source/configuration was not recovered.

## What remains unfinished

The package narrows the source request to concrete module names and hashes. It
does not finish board support, switch/SFP/offload drivers, safe PoE support,
bootloader-preserving flash layout, AirLink root filesystem/image packaging,
watchdog/temperature integration or recovery. Exact-board RAM boot has not been
tested. `ram_boot_verified` and `installable_firmware` remain false.

The MIPS package provides no ARM netPower 16P board validation. Renaming this
package or its extracted kernel to `kernel.bin` or `sysupgrade.bin` would not
produce AirLink firmware. No such artifact was created.

Next evidence: matching kernel configuration and platform/driver source or
documented interfaces, vendor-confirmed r2 board mapping and flash geometry, then
a serial boot capture and controlled RAM-boot/recovery test with local access.
The [vendor request](vendor-source-request.txt) is updated but remains unsent.

## Reproduce the structural inspection

With Python 3 and a separately downloaded copy of the vendor package:

```sh
python3 scripts/inspect_npk.py /path/to/uploaded.npk \
  --compare /path/to/vendor-download.npk > /tmp/npk-inspection.json
PYTHONPATH=backend backend/.venv/bin/python -m pytest backend/tests/test_npk_inspector.py -q
```

The inspector writes JSON to stdout, has no extraction/install/network function,
and bounds input, container counts and decompression. The format layout was checked
against [OpenWrt's NPK utility](https://lxr.openwrt.org/source/firmware-utils/src/npk_pack_kernel.c);
that utility's existence does not establish CRS112 support.

The [review manifest](evidence/npk-6.49.19-review.json) records file hashes, selected
module metadata, offsets and limitations. SquashFS observations additionally used
`unsquashfs -s`, `unsquashfs -ll` and `unsquashfs -cat` on type-21 payload at NPK
offset 4096, length 11,038,720. Archive entries were never materialized into system
paths. All offsets in this report refer to the inspected file, not device flash.
