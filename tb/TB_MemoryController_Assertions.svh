//                              -*- Mode: SystemVerilog -*-
// Filename        : TB_MemoryController_Assertions.sv
// Description     : Assertions for the MemoryController module.
// Author          : Stephan Proß
// Created On      : Tue Dec 27 16:32:31 2022
// Last Modified By: Stephan Proß
// Last Modified On: Tue Dec 27 16:32:31 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!



// property outputs_after_reset_prop;
//    @(posedge CLK_I)
//      (!RST_NI) |-> ##[0:1]
//        !turn && write_allow && read_allow;
// endproperty // outputs_after_reset_prop
// assert property(outputs_after_reset_prop)
//   else
//     $error("%m Output signals did not reset to correct values");

property pointer_validity_prop;
   @(posedge CLK_I) disable iff(!RST_NI || !MODE_I)
     log_rptr != (sys_wptr + 1) % TRB_DEPTH
                 && log_wptr != log_rptr
                 && sys_rptr != (log_wptr +1) % TRB_DEPTH
                 && sys_wptr != sys_rptr;
endproperty // pointer_validity_prop
assert property(pointer_validity_prop);

// property system_write_turn_prop;
//    @(posedge CLK_I) disable iff(!RST_NI)
//      (!write_turn)
//      |-> write_addr == sys_wptr && write_data == WRITE_DATA_I;
// endproperty // system_write_turn_prop
// assert property(system_write_turn_prop);

// property system_read_turn_prop;
//    @(posedge CLK_I) disable iff(!RST_NI)
//      (!read_turn)
//      |-> read_addr == sys_rptr
//                     |-> ##1 READ_DATA_O == $past(read_data);
// endproperty // system_read_turn_prop
// assert property(system_read_turn_prop);

// property logger_turn_prop;
//    @(posedge CLK_I) disable iff(!RST_NI)
//      (write_turn)
//      |-> read_addr == log_rptr && write_addr == log_wptr && write_data == LOGGER_DATA_I
//                     |-> ##1 LOGGER_DATA_O == $past(read_data);
// endproperty // logger_turn_prop
// assert property(logger_turn_prop);
