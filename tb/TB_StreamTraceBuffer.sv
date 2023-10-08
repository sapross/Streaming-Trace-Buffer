//     -*- Mode: SystemVerilog -*-
// Filename        : TB_MemoryController.sv
// Description     : Testbench for MemoryController module.
// Author          : Stephan Proß
// Created On      : Wed Dec 14 11:33:16 2022
// Last Modified By: Stephan Proß
// Last Modified On: Wed Dec 14 11:33:16 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!


import DTB_PKG::*;

module TB_StreamTraceBuffer (  /*AUTOARG*/);

  localparam integer unsigned WRITE_WIDTH = 8;
  localparam integer unsigned READ_WIDTH = 8;

  logic                          clk;
  logic                          rst_n;

  logic                          status_ready;
  logic                          status_valid;
  status_t                       status;

  logic                          control_ready;
  logic                          control_valid;
  control_t                      control;


  logic                          stb_data_ready;
  logic                          stb_data_valid;
  logic     [     TRB_WIDTH-1:0] stb_data;


  logic                          sys_data_ready;
  logic                          sys_data_valid;
  logic     [     TRB_WIDTH-1:0] sys_data;


  // FPGA side
  logic                          fpga_clk;
  logic                          trace_ready;
  logic                          trace_valid;
  logic     [TRB_MAX_TRACES-1:0] trace;

  logic                          stream_ready;
  logic                          stream_valid;
  logic     [TRB_MAX_TRACES-1:0] stream;


  initial begin
    clk = 0;
  end
  always begin
    #10 clk = ~clk;
  end

  integer unsigned fpga_clk_frequency;
  integer unsigned fpga_clk_offset;
  integer unsigned fpga_clk_count;

  initial begin
    fpga_clk = 0;
    fpga_clk_count = 0;
    fpga_clk_offset = 0;
    fpga_clk_frequency = 20;
  end
  always begin
    if (fpga_clk_offset > 0) begin
      #1 fpga_clk_offset--;
    end else begin
      #1 fpga_clk_count++;
      if (fpga_clk_count > fpga_clk_frequency / 2) begin
        fpga_clk = ~fpga_clk;
        fpga_clk_count = 0;
      end
    end
  end



  initial begin
    rst_n = 0;

    status_ready = 0;
    control_valid = 0;
    control = CONTROL_DEFAULT;

    stb_data_ready = 0;
    sys_data_valid = 0;
    sys_data = '0;

    trace_valid = 0;
    trace = '0;
    stream_ready = 0;

    #20 rst_n = 1;
  end

  StreamTraceBuffer DUT (
      .CLK_I              (clk),
      .RST_NI             (rst_n),
      .STATUS_READY_I     (status_ready),
      .STATUS_VALID_O     (status_valid),
      .STATUS_O           (status),
      .CONTROL_READY_O    (control_ready),
      .CONTROL_VALID_I    (control_valid),
      .CONTROL_I          (control),
      .DATA_READY_I       (stb_data_ready),
      .DATA_VALID_O       (stb_data_valid),
      .DATA_O             (stb_data),
      .DATA_READY_O       (sys_data_ready),
      .DATA_VALID_I       (sys_data_valid),
      .DATA_I             (sys_data),
      .FPGA_CLK_I         (fpga_clk),
      .FPGA_TRACE_VALID_I (trace_valid),
      .FPGA_TRACE_READY_O (trace_ready),
      .FPGA_TRACE_I       (trace),
      .FPGA_STREAM_READY_I(stream_ready),
      .FPGA_STREAM_VALID_O(stream_valid),
      .FPGA_STREAM_O      (stream)
  );

  // Trigger reset and set DUT inputs to defaults.
  task reset_to_default;
    rst_n = 0;

    status_ready = 0;
    control_valid = 0;
    control = CONTROL_DEFAULT;

    stb_data_ready = 0;
    sys_data_valid = 0;
    sys_data = '0;

    trace_valid = 0;
    trace = '0;
    stream_ready = 0;

  endtask  // reset_to_default

  task fpga_serialize(input int unsigned bit_rate, input logic [TRB_WIDTH-1:0] word);
    for (int i = 0; i < $size(word); i += bit_rate) begin
      trace <= '0;
      for (int j = 0; j < bit_rate; j++) begin
        trace[j] <= word[i+j];
      end
      @(posedge fpga_clk);
    end
  endtask  // fpga_serialize

  task fpga_deserialize(input int unsigned bit_rate, output logic [TRB_WIDTH-1:0] word);
    for (int i = 0; i < $size(word); i += bit_rate) begin
      while (!stream_valid || !stream_ready) begin
        stream_ready <= 0;
        if (stream_valid) begin
          stream_ready <= 1;
        end
        @(posedge fpga_clk);
      end
      for (int j = 0; j < bit_rate; j++) begin
        word[i+j] <= stream[j];
      end
      @(posedge fpga_clk);
    end
    stream_ready <= 0;
  endtask  // fpga_deserialize

  task write_control(input control_t value);
    $display("Ready-Valid write of control register.");
    control_valid <= 1;
    control <= value;
    while (!control_ready) begin
      @(posedge clk);
    end
    control_valid <= 0;
    @(posedge clk);
  endtask  // write_control

  task write_data(input logic [TRB_WIDTH-1:0] value);
    $display("Ready-Valid write of data register.");
    sys_data_valid <= 1;
    sys_data <= value;
    while (!sys_data_ready) begin
      @(posedge clk);
    end
    sys_data_valid <= 0;
    @(posedge clk);
  endtask  // write_data

  task read_status(output status_t value);
    $display("Ready-Valid stream_ready of status register.");
    status_ready <= 1;
    while (!status_valid) begin
      @(posedge clk);
    end
    value <= status;
    status_ready <= 0;
    @(posedge clk);
  endtask  // read_status
  task read_data(output logic [TRB_WIDTH-1:0] value);
    $display("Ready-Valid stream_ready of data register.");
    stb_data_ready <= 1;
    while (!stb_data_valid) begin
      @(posedge clk);
    end
    value <= stb_data;
    stb_data_ready <= 0;
    @(posedge clk);
  endtask  // read_data

  logic [TRB_DEPTH-1:0] word;
  logic [TRB_DEPTH-1:0] array[TRB_WIDTH-1:0];

  task test_trace_mode_sys_read;

    control_t cntrl;
    status_t  stat;
    int       offset;
    offset <= 0;
    for (int i = 0; i < TRB_DEPTH; i++) begin
      array[i] = i;
    end

    $display("[ %0t ] Test: Trace readout after Trigger .", $time);
    reset_to_default();
    @(posedge clk);
    rst_n <= 1;
    cntrl <= CONTROL_DEFAULT;
    stat <= STATUS_DEFAULT;
    // Put STB in Trace mode
    cntrl.trg_mode <= trace_mode;
    // Set num traces to the highest amount to speed up deserialization
    cntrl.trg_num_traces <= 2 ** TRB_MAX_TRACES - 1;
    // Set delay to zero for lowest trigger delay.
    cntrl.trg_delay <= 1;


    @(posedge clk);
    offset <= 1 + ((cntrl.trg_delay) * (TRB_DEPTH - 1)) / (2 ** TRB_DELAY_BITS - 1);
    write_control(cntrl);

    @(posedge fpga_clk);
    for (int i = 0; i < TRB_DEPTH; i++) begin
      fpga_serialize(2 ** cntrl.trg_num_traces, i);
    end
    trace_valid <= 1;
    for (int i = 0; i < TRB_DEPTH; i++) begin
      fpga_serialize(2 ** cntrl.trg_num_traces, 31);
    end

    @(posedge clk);
    while (!status_valid) begin
      @(posedge clk);
    end
    read_status(stat);
    $display("%d", offset);
    for (int i = 0; i < TRB_DEPTH; i++) begin
      read_data(word);
      assert (word == array[(offset+i)%TRB_DEPTH])
      else $error("%m stream_ready %8h, expected %8h", word, array[(offset+i)%TRB_DEPTH]);
    end

  endtask  // test_random_read

  task test_stream_mode_sys_write;

    control_t cntrl;
    status_t  stat;
    int       offset;
    offset <= 0;
    for (int i = 0; i < TRB_DEPTH; i++) begin
      array[i] = i;
    end

    $display("[ %0t ] Test: Trace readout after Trigger .", $time);
    reset_to_default();
    // Put STB in Write-Only Stream mode
    cntrl.trg_mode <= w_stream_mode;
    // Set num traces to 8 bits parallel.
    cntrl.trg_num_traces <= 3;
    // Set delay to zero for lowest trigger delay.
    cntrl.trg_delay <= 0;
    @(posedge clk);
    rst_n <= 1;


    @(posedge clk);
    write_control(cntrl);

    @(posedge clk);
    for (int i = 0; i < TRB_DEPTH; i++) begin
      write_data(array[i]);
    end

    @(posedge fpga_clk);
    for (int i = 0; i < TRB_DEPTH; i++) begin
      fpga_deserialize(2 ** cntrl.trg_num_traces, array[i]);
    end

    @(posedge clk);
    read_status(stat);
    $display("%d", offset);
    for (int i = 0; i < TRB_DEPTH; i++) begin
      assert (array[i] == i)
      else $error("%m stream_ready %8h, expected %8h", array[i], i);
    end

  endtask  // test_random_read
  initial begin
    #20 test_stream_mode_sys_write();
    test_trace_mode_sys_read();
    $display("[ %0t ] All tests done.", $time);

    $dumpfile("TB_MEMORYCONTROLLER_DUMP.vcd");
    $dumpvars;
  end

endmodule  // TB_StreamTraceBuffer
