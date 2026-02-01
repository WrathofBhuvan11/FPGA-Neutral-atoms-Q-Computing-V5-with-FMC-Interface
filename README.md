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
3×3 ROI Grid Layout
When trigger fires at (Qx, Qy):


text
     X coords:      Qx-1    Qx    Qx+1
                    ┌─────┬─────┬─────┐
Y = Qy-2 (Top)      │[2,0]│[2,1]│[2,2]│  ← Top row
                    ├─────┼─────┼─────┤
Y = Qy-1 (Middle)   │[1,0]│[1,1]│[1,2]│  ← Middle row (CENTER!)
                    ├─────┼─────┼─────┤
Y = Qy   (Bottom)   │[0,0]│[0,1]│[0,2]│  ← Bottom row
                    └─────┴─────┴─────┘
                            ↑
                        (Qx, Qy) is HERE!
                        Bottom-Center position [0,1]

```
