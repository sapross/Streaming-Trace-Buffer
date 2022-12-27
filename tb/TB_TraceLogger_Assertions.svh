//                              -*- Mode: SystemVerilog -*-
// Filename        : TB_TraceLogger_assertions.sv
// Description     : Assertions for the TraceLogger module.
// Author          : Stephan Proß
// Created On      : Tue Dec 27 16:32:31 2022
// Last Modified By: Stephan Proß
// Last Modified On: Tue Dec 27 16:32:31 2022
// Update Count    : 0
// Status          : Unknown, Use with caution!


property outputs_after_reset_prop;
   @(posedge clk)
     (!reset_n) |-> ##1
       stat == STATUS_DEFAULT &&
             write == 0 &&
             read_ptr == 1 &&
             write_ptr == 0 &&
             dword_out == '0 &&
             mode == 0 &&
             data_out == '0 &&
             load_grant == 0 &&
             num_traces == 0;
endproperty // outputs_after_reset_prop
assert property(outputs_after_reset_prop)
  else
    $error("%m Output signals did not reset to correct values");


property store_permission_valid_prop;
   // Assert that the store is permitted under the right circumstances.
   @(posedge clk) disable iff(!reset_n)
     (write_allow &&
      write_ptr != read_ptr &&
      !trg_delayed) |-> store_perm == 1;
endproperty // store_permission_valid_prop
assert property(store_permission_valid_prop)
  else
    $error ("%m Store permission expected");

property store_permission_invalid_prop;
   @(posedge clk) disable iff(!reset_n)
     (!write_allow ||
      write_ptr == read_ptr ||
      trg_delayed) |-> !store_perm;
endproperty // store_permission_invalid_prop
assert property(store_permission_invalid_prop)
  else
    $error ("%m unexpected store permission");

property load_to_tracer_prop;
   // Assert that the store is permitted under the right circumstances.
   @(posedge clk)
     disable iff(!reset_n ||
                 (read_ptr+1)%TRB_DEPTH == write_ptr)

       (load_request && read_allow) |->
                                         ##[1:2] rw_turn == 1 |->
                                         ##1 load_grant == 1 &&
                                         data_out == $past(dword_in);
endproperty // load_to_tracer_prop
assert property(load_to_tracer_prop)
  else
    $error ("%m load operation did not occur on next rw_turn or is invalid.");

property forbidden_load_to_tracer_prop;
   // Assert that the store is permitted under the right circumstances.
   @(posedge clk)
     disable iff(!reset_n)
       (!read_allow || (read_ptr+1)%TRB_DEPTH == write_ptr ) |->
                                               !load_grant;
endproperty // forbidden_load_to_tracer_prop
assert property(forbidden_load_to_tracer_prop)
  else
    $error ("%m load operation occured while not permitted!.");

property store_to_memory_prop;
   // Assert that a store is followed by a write operation two cycles later
   // if store occured while TraceLogger has RW turn.
   @(posedge clk) disable iff(!reset_n || trg_delayed || !write_allow)
     (store && !trg_delayed && write_allow) |->
       ##[1:2] rw_turn == 1 |->
                        write == 1 &&
                        dword_out == $past(data_in);
endproperty // store_to_memory_prop
assert property(store_to_memory_prop)
  else
    $error ("%m write operation did not occur on next rw_turn or is invalid.");

property forbidden_store_to_memory_prop;
   @(posedge clk) disable iff(!reset_n )
     (trg_delayed || !write_allow) |->
       write == 0;
endproperty // forbidden_store_to_memory_prop
assert property(forbidden_store_to_memory_prop)
  else
    $error ("%m write operation occured while not permitted!");

property write_pointer_increment_prop;
   // Make sure that the write pointer is always incremented after a write operation.
   @(posedge clk) disable iff(!reset_n || trg_delayed || !write_allow)
     (write) |-> ##1
       write_ptr == ($past(write_ptr) + 1) % TRB_DEPTH;
endproperty // write_pointer_increment_prop
assert property(write_pointer_increment_prop)
  else
    $error ("%m Write pointer did not increment after write operation");

int assert_delay;
logic assert_trg_event;
always_ff @(posedge clk) begin : trg_delay_assert_proc
   if (!reset_n) begin
      assert_trg_event <= 0;
   end
   else begin
      if (! trg_event) begin
         assert_delay <= 1 + ((conf.trg_delay+1)*(TRB_DEPTH-1))/ (2**TRB_DELAY_BITS);
         assert (!trg_delayed)
           else
             $error("%m unexpected trg_delayed");
      end
      else begin
         assert_trg_event <= 1;
      end
      if (assert_trg_event == 1) begin
         if (assert_delay > 0) begin
            if(write && rw_turn) begin
               assert_delay <= assert_delay - 1;
            end
            assert (!trg_delayed)
              else
                $error("%m unexpected trg_delayed");
         end
         else begin
            assert (trg_delayed)
              else
                $error("%m trg_delayed expected");
         end
      end
   end
end
