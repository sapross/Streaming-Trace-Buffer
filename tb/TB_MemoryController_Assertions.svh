//                              -*- Mode: SystemVerilog -*-
// Filename        : TB_MemoryController_Assertions.sv
// Description     : Assertions for the MemoryController module.
// Author          : Stephan Proß
// Created On      : Tue Dec 27 16:32:31 2022
// Last Modified By: Stephan Proß
// Last Modified On: Tue Dec 27 16:32:31 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!



property outputs_after_reset_prop;
   @(posedge clk)
     (!reset_n) |-> ##[0:1]
       !turn && write_allow && read_allow;
endproperty // outputs_after_reset_prop
assert property(outputs_after_reset_prop)
  else
    $error("%m Output signals did not reset to correct values");

property read_allow_prop;
   @(posedge clk) disable iff(!RST_NI)
     sys_rptr != log_wptr |-> read_allow;
endproperty // read_allow_prop
assert property(read_allow_prop);

property read_disallow_prop;
   @(posedge clk) disable iff(!RST_NI)
     sys_rptr == log_wptr |-> !read_allow;
endproperty // read_allow_prop
assert property(read_disallow_prop);

property write_allow_prop;
   @(posedge clk) disable iff(!RST_NI)
     (sys_wptr+1) % TRB_DEPTH!= log_rptr |-> write_allow;
endproperty // write_allow_prop
assert property(write_allow_prop);

property write_disallow_prop;
   @(posedge clk) disable iff(!RST_NI)
     (sys_wptr+1) % TRB_DEPTH == log_rptr |-> !write_allow;
endproperty // write_disallow_prop
assert property(write_disallow_prop);

property system_turn_prop;
   @(posedge clk) disable iff(!RST_NI)
     (!turn)
     |-> read_addr == sys_rptr && write_addr == sys_wptr && write_dara == LOGGER_DATA_I
                    |-> ##1 READ_DATA_O <= read_data;
endproperty // system_turn_prop
assert property(system_turn_prop);

property logger_turn_prop;
   @(posedge clk) disable iff(!RST_NI)
     (!turn)
     |-> read_addr == log_rptr && write_addr == log_wptr && write_dara == WRITE_DATA_I
                    |-> ##1 LOGGER_DATA_O <= read_data;
endproperty // logger_turn_prop
assert property(logger_turn_prop);
