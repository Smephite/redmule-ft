/*
 * Copyright (C) 2024-2025 ETH Zurich and University of Bologna
 *
 * Licensed under the Solderpad Hardware License, Version 0.51
 * (the "License"); you may not use this file except in compliance
 * with the License. You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * SPDX-License-Identifier: SHL-0.51
 *
 * Authors:  Maurus Item     <itemm@student.ethz.ch>
 *
 * RedMulE TCDM Deduplication for Memory Writes Only
 */

`include "hci_helpers.svh"
`include "common_cells/registers.svh"

module redmule_deduplicator
  import hci_package::*;
#(
  parameter MAX_MEMORY_DELAY = 128,
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0
) (
  input logic                       clk_i,
  input logic                       rst_ni,
  hci_core_intf.target    tcdm_target,
  hci_core_intf.initiator tcdm_initiator
);

  localparam int unsigned AW = `HCI_SIZE_GET_AW(tcdm);
  localparam int unsigned DW = `HCI_SIZE_GET_DW(tcdm);
  localparam int unsigned UW = `HCI_SIZE_GET_UW(tcdm);
  localparam int unsigned EW = `HCI_SIZE_GET_EW(tcdm);
  localparam int unsigned IW = `HCI_SIZE_GET_IW(tcdm);
  localparam int unsigned EHW = `HCI_SIZE_GET_EHW(tcdm);

  //////////////////////////////////////////////////////////////////////////////////
  // Forward Deduplication

  // Store request address and write enable on handshake
  logic [AW-1:0] add_q;
  logic wen_q;

  `FFL(add_q, tcdm_target.add, tcdm_target.req && tcdm_target.gnt, '0);
  `FFL(wen_q, tcdm_target.wen, tcdm_target.req && tcdm_target.gnt, '0);

  // Drop requests if they are the same as the previous one and it is a store (wen = 0)
  logic drop_request;
  assign drop_request = tcdm_target.req && (tcdm_target.add == add_q && tcdm_target.wen == wen_q);

  always_comb begin
    if (drop_request) begin
      tcdm_initiator.req  = 1'b0;
      tcdm_initiator.ereq = 1'b0;

      tcdm_target.gnt     = 1'b1; // Reverse Connection
      tcdm_target.egnt    = 1'b1; // Reverse Connection

    end else begin
      tcdm_initiator.req  = tcdm_target.req;
      tcdm_initiator.ereq = tcdm_target.ereq;
      tcdm_target.gnt     = tcdm_initiator.gnt; // Reverse Connection
      tcdm_target.egnt    = tcdm_initiator.egnt; // Reverse Connection
    end
  end

  ////////////////////////////////////////////////////////////////////////////////
  // Replication storage

  // Find all outgoing memory read requests store a bit if it was dropped or not
  // and use output from can if so

  logic replicate_fifo_push, replicate_fifo_pop;
  logic replicate_fifo_empty, replicate_fifo_full;

  // Whenever a read request was done push to fifo
  assign replicate_fifo_push = tcdm_target.req && tcdm_target.gnt && tcdm_target.wen;

  // Whenever we send a response pop from 
  assign replicate_fifo_pop = tcdm_target.r_valid && tcdm_target.r_ready && ~replicate_fifo_empty;

  fifo_v3 #(
    .FALL_THROUGH ( 0                ), // Every response can only be sent in the next cycle at the earliest
    .DATA_WIDTH   ( 1                ),
    .DEPTH        ( MAX_MEMORY_DELAY )
  ) i_replicate_fifo (
    .clk_i,
    .rst_ni,
    .flush_i     (                 1'b0 ),
    .testmode_i  (                 1'b0 ),
    .data_i      ( drop_request         ),
    .push_i      ( replicate_fifo_push  ),
    .data_o      ( drop_request_out     ),
    .pop_i       ( replicate_fifo_pop   ),
    .usage_o     ( /* Unused */         ),
    .full_o      ( replicate_fifo_full  ),
    .empty_o     ( replicate_fifo_empty )
  );

  ////////////////////////////////////////////////////////////////////////////////
  // Replication Buffer FIFO

  // In order to be able to inject data into the responses
  // we need to hold back other responses, but the memory side is not stallable
  // So we use a buffer to hold those back. 

  // Struct to hold backwards data
  typedef struct packed {
    logic  [DW-1:0]  r_data;
    logic  [UW-1:0]  r_user;
    logic  [IW-1:0]  r_id;
    logic            r_opc;
    logic  [EW-1:0]  r_ecc;
    logic  [EHW-1:0] r_evalid;
  } fifo_data_t;

  fifo_data_t response_data, response_data_buffered, response_data_buffered_q;

  // Assign data to from memory side to struct for processing
  assign response_data.r_data   = tcdm_initiator.r_data;
  assign response_data.r_user   = tcdm_initiator.r_user;
  assign response_data.r_id     = tcdm_initiator.r_id;
  assign response_data.r_opc    = tcdm_initiator.r_opc;
  assign response_data.r_ecc    = tcdm_initiator.r_ecc;
  assign response_data.r_evalid = tcdm_initiator.r_evalid;

  // Backwards FIFO so Handshake can be respected
  logic buffer_fifo_push, buffer_fifo_pop;
  logic buffer_fifo_empty, buffer_fifo_full;

  // Handshake logic
  logic buffered_valid, buffered_ready;

  assign buffer_fifo_push = tcdm_initiator.r_valid & ~buffer_fifo_full;
  assign buffer_fifo_pop  = buffered_ready & ~buffer_fifo_empty;

  assign tcdm_initiator.r_ready = ~buffer_fifo_full; // This might not be respected by the upstrea memory, we assign it anyway
  assign tcdm_initiator.r_eready = ~buffer_fifo_full; // This might not be respected by the upstrea memory, we assign it anyway
  assign buffered_valid = ~buffer_fifo_empty;

  fifo_v3 #(
    .FALL_THROUGH ( 1                  ),
    .DATA_WIDTH   ( $bits(fifo_data_t) ),
    .DEPTH        ( 2                  )
  ) i_buffer_fifo (
    .clk_i,
    .rst_ni,
    .flush_i     (                        ),
    .testmode_i  (                        ),
    .data_i      ( response_data          ),
    .push_i      ( buffer_fifo_push       ),
    .data_o      ( response_data_buffered ),
    .pop_i       ( buffer_fifo_pop        ),
    .usage_o     ( /* Unused */           ),
    .full_o      ( buffer_fifo_full       ),
    .empty_o     ( buffer_fifo_empty      )
  );

  ////////////////////////////////////////////////////////////////////////////////
  // Replication Generation

  // Store current result so we can use it again for replication if required
  `FFL(response_data_buffered_q, response_data_buffered,   tcdm_initiator.r_valid && tcdm_initiator.r_ready, '0);

  // Data / Handshake Injection
  always_comb begin
    if (drop_request_out && !replicate_fifo_empty) begin
      tcdm_target.r_valid     = 1'b1;

      buffered_ready          = 1'b0; // Reverse Connection

      tcdm_target.r_evalid    = response_data_buffered_q.r_evalid;
      tcdm_target.r_data      = response_data_buffered_q.r_data;
      tcdm_target.r_ecc       = response_data_buffered_q.r_ecc;
      tcdm_target.r_user      = response_data_buffered_q.r_user;
      tcdm_target.r_id        = response_data_buffered_q.r_id;
      tcdm_target.r_opc       = response_data_buffered_q.r_opc;
    end else begin
      tcdm_target.r_valid     = buffered_valid;

      buffered_ready          = tcdm_target.r_ready; // Reverse Connection

      tcdm_target.r_evalid    = response_data_buffered.r_evalid;
      tcdm_target.r_data      = response_data_buffered.r_data;
      tcdm_target.r_ecc       = response_data_buffered.r_ecc;
      tcdm_target.r_user      = response_data_buffered.r_user;
      tcdm_target.r_id        = response_data_buffered.r_id;
      tcdm_target.r_opc       = response_data_buffered.r_opc;
    end
  end

  //////////////////////////////////////////////////////////////////////////////////
  // Assign all other values without difference

  // Forward path
  // Data
  assign tcdm_initiator.add      = tcdm_target.add;
  assign tcdm_initiator.wen      = tcdm_target.wen;
  assign tcdm_initiator.data     = tcdm_target.data;
  assign tcdm_initiator.be       = tcdm_target.be;
  assign tcdm_initiator.user     = tcdm_target.user;
  assign tcdm_initiator.id       = tcdm_target.id;

  // ECC Data
  assign tcdm_initiator.ecc      = tcdm_target.ecc;

endmodule // redmule_deduplicator
