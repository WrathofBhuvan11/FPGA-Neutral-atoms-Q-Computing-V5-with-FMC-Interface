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
