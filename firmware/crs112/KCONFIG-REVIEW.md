# Proposed kernel options review

Reviewed 2026-11-10. This records the user's proposed options as research input;
none was installed as a board defconfig. No kernel build or hardware test was run.

| Proposed option | Assessment |
| --- | --- |
| `CONFIG_MIPS=y` | Consistent with the reported processor and inspected vendor ELF. |
| `CONFIG_CPU_MIPS32_R2=y` | Consistent with vendor kernel ELF flags and module vermagic; not sufficient for board support. |
| `CONFIG_CPU_BIG_ENDIAN=y` | Consistent with reported `mipsbe` and the ELF byte order. |
| `CONFIG_MIPS_MT_SMP=n` | Disabling MT SMP is consistent with the reported single CPU. A generated `.config` normally writes `# CONFIG_MIPS_MT_SMP is not set`; this alone does not disable every SMP option. |
| `CONFIG_SYS_HAS_CPU_MIPS32_R2=y` | Hidden platform capability; let the selected platform's Kconfig establish it. |
| `CONFIG_WEAK_ORDERING=y` | Hidden CPU capability; do not force it without matching Kconfig selections. |
| `CONFIG_MIPS_L1_CACHE_SHIFT=5` | Not verified. The historical vendor MIPS config uses `4`, and its Kconfig defaults to `4` for `MIPS_MIKROTIK`. This is a configuration discrepancy, not proof of physical cache-line size or permission to substitute `4` blindly. |
| `CONFIG_ATH79=y` | No reviewed evidence establishes ATH79 as the CRS112 MUSIC platform target. Upstream describes this platform for AR71XX/AR724X/AR913X. |
| `CONFIG_SOC_QCA851X=y` | No definition found in the inspected vendor mirror or tracked OpenWrt `target/linux` files. An assignment alone cannot implement SoC support; any external patch defining it needs separate review. |
| `CONFIG_PCI=y`, `CONFIG_PCI_AR724X=y` | No evidence here establishes the AR724x PCI controller for CRS112 r2. Generic PCI support does not supply the MUSIC switch driver. |

The pinned historical vendor mirror contains `CONFIG_MIPS_MIKROTIK=y` in
`patche_and_config_2020_03_20/configs/mips.config`, together with big-endian and
MIPS32 Release 2 selections. Its `arch/mips/rb/Makefile` builds `music.o` and
`music_irq.o`, while `prom.c` assigns `ccs112` and `ccs112r4` to the MUSIC machine
group. This is a candidate vendor path, **not a verified replacement defconfig**.
Do not use the mirror's separate `mmips.config`: the reported device is `mipsbe`.

References:

- [Upstream MIPS Kconfig](https://github.com/torvalds/linux/blob/master/arch/mips/Kconfig), checked 2026-11-10.
- [Pinned historical vendor MIPS config](https://github.com/robimarko/routeros-GPL/blob/63164edb5398041b2da4aabdcfe0d0c3fdd00f06/patche_and_config_2020_03_20/configs/mips.config).
- [Pinned historical vendor Kconfig](https://github.com/robimarko/routeros-GPL/blob/63164edb5398041b2da4aabdcfe0d0c3fdd00f06/linux_3_3_5_patch_RouterOS644/arch/mips/Kconfig).
- [Source provenance and limitations](VENDOR-SOURCE-REVIEW.md) and [uploaded binary findings](NPK-REVIEW.md).

The mirror's historical configuration is not authenticated as the configuration
of the installed 6.48.6 kernel or uploaded 6.49.19 kernel. The remaining work is to
establish matching sources/configuration, complete platform and driver integration,
and validate exact-board RAM boot and recovery. Firmware readiness remains false.
