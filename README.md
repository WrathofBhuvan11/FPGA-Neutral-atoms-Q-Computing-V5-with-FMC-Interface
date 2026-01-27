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
