# FPGA-Neutral-atoms-Q-Computing-V5-with-FMC-Interface
parameterised full mode
2 pixel system

```
3×3 ROI for Qubit with (Qx=100, Qy=100):

        X: 99     100     101
      ┌───────┬────────┬────────┐
Y: 98 │ (99,98)│(100,98)│(101,98)│  ← Top Row (Qy-2)
      ├───────┼────────┼────────┤
   99 │ (99,99)│(100,99)│(101,99)│  ← Mid Row (Qy-1)
      ├───────┼────────┼────────┤
  100 │(99,100)│(100,100)│(101,100)│  ← Bot Row (Qy)
      └───────┴────────┴────────┘
                  ↑         ↑
          (Qx,Qy) stored  Trigger
          BOTTOM-CENTER   position
```



```
fmc_receiver.sv - Demux @ 510 MHz
Demux (8->2 every cycle):
┌─────────────────────────────────────────────────────┐
│ 85 MHz: Receive 8 pixels [P7 P6 P5 P4 P3 P2 P1 P0] │
│ 510 MHz Cycle 0: Output [P1 P0]   @ X              │
│ 510 MHz Cycle 1: Output [P3 P2]   @ X+2            │
│ 510 MHz Cycle 2: Output [P5 P4]   @ X+4            │
│ 510 MHz Cycle 3: Output [P7 P6]   @ X+6            │
└─────────────────────────────────────────────────────┘
                      │
                      ▼
        2 pixels/cycle @ 510 MHz (parallel)

Effective throughput: 510 MHz × 2 px = 1,020 Mpx/s

```
