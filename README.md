# FPGA-Neutral-atoms-Q-Computing-V5-with-FMC-Interface
parameterised v4= v5


```
// fmc_receiver_base.sv - State Machine @ 510 MHz
State Machine (3 cycles per group):
┌─────────────────────────────────────────────────────┐
│ Cycle 0: IDLE       - Read FIFO (24-bit)           │
│ Cycle 1: OUTPUT_P0  - Output pixel[7:0]   @ X      │  
│ Cycle 2: OUTPUT_P1  - Output pixel[15:8]  @ X+1    │
│ Cycle 3: OUTPUT_P2  - Output pixel[23:16] @ X+2    │
└─────────────────────────────────────────────────────┘
                      │
                      ▼
        1 pixel/cycle @ 510 MHz (sequential)
        
Effective throughput: 85 MHz × 3 px = 255 Mpx/s
```
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
