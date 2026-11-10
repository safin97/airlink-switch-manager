# netPower 16P — CRS318-16P-2S+OUT

**Research workspace only. No selected build target or bootable image.**

MikroTik's [product specification](https://mikrotik.com/product/netpower_16p) lists
32-bit ARM, 98DX226S, two 800 MHz cores, 256 MB RAM, 16 MB flash, 16 Gigabit Ethernet
ports with PoE-out, two 10G SFP+ ports, voltage and CPU temperature monitoring.
These vendor specifications do not establish a Linux board implementation.

The [model manual](https://help.mikrotik.com/docs/spaces/UM/pages/28606548/netPower+16P)
describes RouterOS/SwOS boot selection, serial console and RouterBOOT/Netinstall recovery.
Its documented backup-loader behavior and network recovery still need validation on the
actual board revision. Do not hold reset or change boot settings during monitoring.

| Component | Evidence/status |
|---|---|
| PCB revision / RouterBOOT | Physical board and boot log missing |
| CPU / device tree | Vendor 98DX226S; exact-board upstream DTS not found in checked architecture tree |
| Flash | Vendor capacity known; geometry, partitions, addresses and loader preservation unverified |
| Ethernet / ASIC | 16 copper + 2 SFP+; Linux port mapping, CPU interface and firmware requirements unverified |
| SFP / hardware offload | PHY/SerDes, module buses and switchdev/offload integration unfinished |
| PoE | Controller protocol, voltage-selection logic and safe driver unfinished |
| Root filesystem / image | No initramfs build or persistent packaging; accepted RouterBOOT image format unverified |
| Watchdog / sensors | RouterOS monitoring supported in application; Linux integration unverified |
| Recovery | Vendor procedure referenced; exact hardware recovery and RAM boot not tested |

Related 98DX3236/CRS3xx device trees are research references only. Do not substitute
CRS305, CRS326, CRS328 or netPower 15FR firmware. Follow the exact evidence list and
RAM-boot gates in [../README.md](../README.md). Store reviewed, redacted evidence in
`evidence/`, with board revision, capture date, source and hashes.
