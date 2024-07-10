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
  parameter hci_size_parameter_t `HCI_SIZE_PARAM(tcdm) = '0
) (
  input logic                       clk_i,
  input logic                       rst_ni,
  hci_core_intf.target    tcdm_target,
  hci_core_intf.initiator tcdm_initiator
);

  localparam int unsigned AW = `HCI_SIZE_GET_AW(tcdm);

  //////////////////////////////////////////////////////////////////////////////////
  // Forward Deduplication

  // Store request address and write enable on handshake
  logic [AW-1:0] add_q;
  logic wen_q;

  `FFL(add_q, tcdm_target.add, tcdm_target.req && tcdm_target.gnt, '0);
  `FFL(wen_q, tcdm_target.wen, tcdm_target.req && tcdm_target.gnt, '0);

  // Drop requests if they are the same as the previous one and it is a store (wen = 0)
  logic drop_request;
  assign drop_request = tcdm_target.req && (tcdm_target.add == add_q && !tcdm_target.wen && !wen_q);

  always_comb begin
    if (drop_request) begin
      tcdm_initiator.req  = 1'b0;
      tcdm_target.gnt     = 1'b1; // Reverse Connection
    end else begin
      tcdm_initiator.req  = tcdm_target.req;
      tcdm_target.gnt     = tcdm_initiator.gnt; // Reverse Connection
    end
  end

  //////////////////////////////////////////////////////////////////////////////////
  // Assign all other values without difference

  // Forward path
  // Handshake

  // Data
  assign tcdm_initiator.add      = tcdm_target.add;
  assign tcdm_initiator.wen      = tcdm_target.wen;
  assign tcdm_initiator.data     = tcdm_target.data;
  assign tcdm_initiator.be       = tcdm_target.be;
  assign tcdm_initiator.user     = tcdm_target.user;
  assign tcdm_initiator.id       = tcdm_target.id;

  // ECC Handshake
  assign tcdm_initiator.ereq     = tcdm_target.ereq;
  assign tcdm_target.egnt        = tcdm_initiator.egnt; // Reverse Connection

  // ECC Data
  assign tcdm_initiator.ecc      = tcdm_target.ecc;

  // Return path
  // Hanshake
  assign tcdm_target.r_valid     = tcdm_initiator.r_valid;
  assign tcdm_initiator.r_ready  = tcdm_target.r_ready; // Reverse Connection

  // Data
  assign tcdm_target.r_data      = tcdm_initiator.r_data;
  assign tcdm_target.r_user      = tcdm_initiator.r_user;
  assign tcdm_target.r_id        = tcdm_initiator.r_id;
  assign tcdm_target.r_opc       = tcdm_initiator.r_opc;

  // ECC Handhake
  assign tcdm_target.r_evalid    = tcdm_initiator.r_evalid;
  assign tcdm_initiator.r_eready = tcdm_target.r_eready; // Reverse Connection

  // ECC Data
  assign tcdm_target.r_ecc       = tcdm_initiator.r_ecc;

endmodule // redmule_deduplicator
