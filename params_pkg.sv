package params_pkg;
    // ----------------------------------------------
    // Image Configuration
    // ----------------------------------------------
    parameter int IMAGE_WIDTH  = 512;
    parameter int IMAGE_HEIGHT = 512;
    parameter int PIXEL_DEPTH  = 8;
    
    // Derived: Coordinate bit width
    parameter int COORD_WIDTH = $clog2(IMAGE_WIDTH > IMAGE_HEIGHT ? 
                                       IMAGE_WIDTH : IMAGE_HEIGHT);
    
    // ----------------------------------------------
    // Qubit Array Configuration
    // ----------------------------------------------
    parameter int NUM_QUBITS = 100;
    
    // Derived: Qubit index width
    parameter int QUBIT_ID_WIDTH = $clog2(NUM_QUBITS);
    
    // Grid layout (for rectangular arrays)
    parameter int GRID_COLS = 10;  // Number of columns
    parameter int GRID_ROWS = 10;  // Number of rows
    
    // Qubit positioning
    parameter int QUBIT_START_X = 100;  // Starting X coordinate
    parameter int QUBIT_START_Y = 100;  // Starting Y coordinate
    parameter int QUBIT_SPACING = 20;   // Pixel spacing between qubits
    
    // ----------------------------------------------
    // Banking Configuration
    // ----------------------------------------------
    parameter int NUM_BANKS = 4;  // Parallel processing lanes
    
    // Derived: Rows per bank
    parameter int ROWS_PER_BANK = (NUM_QUBITS + NUM_BANKS - 1) / NUM_BANKS;
    
    // Derived: Address width (power-of-2 depth)
    parameter int BANK_DEPTH = 1 << $clog2(ROWS_PER_BANK);
    parameter int BANK_ADDR_WIDTH = $clog2(BANK_DEPTH);
    
    // Derived: Row counter width
    parameter int ROW_COUNT_WIDTH = $clog2(ROWS_PER_BANK);
    
    // ----------------------------------------------
    // ROI Configuration
    // ----------------------------------------------
    parameter int ROI_SIZE = 3;  // 3x3 window
    parameter int ROI_BITS = ROI_SIZE * ROI_SIZE * PIXEL_DEPTH;
    
   
    // Type definitions
    typedef logic [COORD_WIDTH-1:0] coord_t;
    typedef logic [QUBIT_ID_WIDTH-1:0] qubit_id_t;
    
endpackage
