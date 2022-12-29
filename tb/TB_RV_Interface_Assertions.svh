//                              -*- Mode: SystemVerilog -*-
// Filename        : TB_RV_Register_Assertions.sv
// Description     : Assertions for the RV_Regiser module.
// Author          : Stephan Proß
// Created On      : Tue Dec 27 16:32:31 2022
// Last Modified By: Stephan Proß
// Last Modified On: Tue Dec 27 16:32:31 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!

// Assert that a reset causes the correct values visible at the outputs.
property outputs_after_reset_prop;
   @(posedge clk)
     (!rst_n) |-> ##[0:1]
       !read_valid &&
         !write_ready &&
           !update;
endproperty // outputs_after_reset_prop
assert property(outputs_after_reset_prop)
  else
    $error("%m output signals did not reset to correct values");

// Assert that a read ready by system is followed by read valid.
property read_ready_to_valid_prop;
   @(posedge clk) disable iff (!rst_n || !read_enable)
     read_ready && !read_valid
       |-> ##1 read_valid;
endproperty // read_ready_to_valid_prop
assert property(read_ready_to_valid_prop)
  else
    $error("%m read valid did not appear after read ready");

property read_finish_prop;
      @(posedge clk) disable iff (!rst_n || !read_enable)
     read_ready && read_valid
       |-> ##1 !read_valid;
endproperty // read_finish_prop
assert property(read_finish_prop)
  else
    $error("%m read valid did not disappear after read ready");

// Assert that a change pulse/signal is followed by
property read_valid_on_change_prop;
      @(posedge clk) disable iff (!rst_n || !read_enable)
     change |-> ##1 read_valid;
endproperty // read_valid_on_change_prop
assert property(read_valid_on_change_prop)
  else
    $error("%m change pulse is not followed by read valid!");

property read_signal_after_success_prop;
      @(posedge clk) disable iff (!rst_n || !read_enable)
     read_ready && read_valid |-> ##1 read;
endproperty // read_signal_after_success_prop
assert property(read_signal_after_success_prop)
  else
    $error("%m read signal did not appear after successful read");

property not_read_prop;
      @(posedge clk) disable iff (!rst_n || !read_enable)
     !read_ready || !read_valid |-> ##1 !read;
endproperty // not_read_prop
assert property(not_read_prop)
  else
    $error("%m unexpected read signal!");

// Assert that a write ready by system is followed by write valid.
property write_enable_gated_ready_prop;
      @(posedge clk) disable iff (!rst_n)
     !write_enable |-> ##1 !write_ready;
endproperty // write_enable_gated_ready_prop
assert property(write_enable_gated_ready_prop)
  else
    $error("%m write ready observed while not enabled");

// Assert that a running write process is finished correctly.
property write_process_prop;
   @(posedge clk) disable iff (!rst_n || !write_enable)
     // Write process starts if we're ready to receive data
     // without being in another write process, i.e. !update.
     write_ready && write_valid && !update
       |-> ##1 write_ready && update
         |-> ##1 !write_ready && !update;
endproperty
assert property(write_process_prop)
  else
    $error("%m write process hasn't been followed correctly");

property write_data_to_output_prop;
   @(posedge clk) disable iff(!rst_n)
    write_data == data_out;
endproperty // write_data_to_output_prop
assert property(write_data_to_output_prop)
  else
    $error("%m data from sysinterface did not appear at data-output");

property input_data_to_read_prop;
  @(posedge clk) disable iff(!rst_n)
    data_in == read_data;
endproperty // input_data_to_read_prop
assert property(input_data_to_read_prop)
  else
    $error("%m data-input did not appear at sysinterface");
