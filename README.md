# FPGA-Neutral-atoms-Q-Computing-V5-with-FMC-Interface
parameterised full mode
2 pixel system


```
Camera scans left-to-right, top-to-bottom:
512×512 pixel image with 100 qubits arranged in 10×10 grid

Example: Qubit #5 at center (120, 100)

     X: 119   120   121        ← Column coordinates
        ┌─────┬─────┬─────┐
 Y: 98  │ TL  │ TC  │ TR  │    ← Top Row (Y-2)
        ├─────┼─────┼─────┤
 Y: 99  │ ML  │ MC  │ MR  │    ← Middle Row (Y-1)
        ├─────┼─────┼─────┤
 Y: 100 │ BL  │ BC  │ BR  │    ← Bottom Row (Y = Qubit Y)
        └─────┴─────┴─────┘
               ↑
          Qubit Center
          
Coordinate Mapping:
- BL (Bottom-Left):   (Qx-1, Qy)   = (119, 100)
- BC (Bottom-Center): (Qx,   Qy)   = (120, 100) ← Qubit position
- BR (Bottom-Right):  (Qx+1, Qy)   = (121, 100)
- ML (Middle-Left):   (Qx-1, Qy-1) = (119, 99)
- MC (Middle-Center): (Qx,   Qy-1) = (120, 99)
- MR (Middle-Right):  (Qx+1, Qy-1) = (121, 99)
- TL (Top-Left):      (Qx-1, Qy-2) = (119, 98)
- TC (Top-Center):    (Qx,   Qy-2) = (120, 98)
- TR (Top-Right):     (Qx+1, Qy-2) = (121, 98)
```
=========================================================================================
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
