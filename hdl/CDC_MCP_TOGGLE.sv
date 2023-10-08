//                              -*- Mode: Verilog -*-
// Filename        : CDC_MCP_TOGGLE.sv
// Description     : Clock domain crossing with multi cycle path formulation.
//                   Makes use of toggle pulse generation.
//                   See Cummings2008 p.25 (http://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf)
// Author          : Stephan Proß
// Created On      : Thu Dec  1 09:18:48 2022
// Last Modified By: Stephan Proß
// Last Modified On: Thu Dec  1 09:18:48 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!


module CDC_MCP_TOGGLE #(
    parameter integer unsigned WIDTH = 5
) (
    // Signals from clock domain A.
    input logic             RST_A_NI,
    input logic             CLK_A_I,
    // Data to be synchronized.
    input logic [WIDTH-1:0] DATA_A_I,
    // Store signal for synchronization.
    input logic             SYNC_A_I,

    // Signals from clock domain B.
    input  logic             CLK_B_I,
    output logic [WIDTH-1:0] DATA_B_O,
    output logic             SYNC_B_O
);

  // ---- Clock Domain A -----
  // Register input DATA_A_I in reg_a
  logic [WIDTH-1:0] reg_a;
  always_ff @(posedge CLK_A_I) begin
    if (!RST_A_NI) begin
      reg_a <= '0;
    end else if (SYNC_A_I) begin
      reg_a <= DATA_A_I;
    end
  end

  //Turn pulse in SYNC_A_I into toggle signal.
  logic toggle_st;
  always_ff @(posedge CLK_A_I) begin : PULSE_GEN
    if (!RST_A_NI) begin
      toggle_st <= 0;
    end else begin
      toggle_st <= SYNC_A_I ^ toggle_st;
    end
  end

  // ---- Clock Domain B -----
  // Using toggle_st, produce a synchronized pulse.
  logic [2:0] q_b;
  always_ff @(posedge CLK_B_I) begin : PULSE_SYNCHRONIZER
    q_b <= {q_b[1:0], toggle_st};
  end

  logic ld_b;
  assign ld_b = q_b[1] ^ q_b[2];

  assign SYNC_B_O = ld_b;
  // Register reg_a in clock domain B using synchronized pulse.
  logic [WIDTH-1:0] reg_b;
  always_ff @(posedge CLK_B_I) begin
    reg_b <= reg_a;
  end
  assign DATA_B_O = reg_b;

endmodule  // CDC_MCP_TOGGLE
