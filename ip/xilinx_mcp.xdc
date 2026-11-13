## ============================================================================
## Multicycle-path constraints for the vendor-neutral sequential operators
## ip/gen_mult_seq.sv and ip/gen_div_seq.sv (Vivado XDC).
## ============================================================================
##
## Each operator registers its operands on `start` (mcp_*_op?_q) and loads its
## result registers (mcp_*_res_q / quo_q / rem_q / dbz_q) exactly LATENCY clock
## edges later. The operands cannot change in between. So the purely
## combinational operator between the two register groups has LATENCY cycles
## to settle:
##     setup multiplier = LATENCY,  hold multiplier = LATENCY - 1
##
## LATENCY = num_cyc - early_start. The values below match how both cores
## instantiate the operators (func_mul / func_div in the OoO core, m_unit in
## the pipeline):
##     multiplier : num_cyc = 5, early_start = 1  ->  LATENCY = 4
##     divider    : num_cyc = 17, early_start = 0 ->  LATENCY = 17
## If you change num_cyc / early_start, update the numbers here. Using a
## smaller setup multiplier than the real latency is always safe; a larger one
## is not.
##
## The boundary registers are dont_touch in the RTL, so these names survive
## synthesis and are not absorbed into DSP pipeline stages.

# ---- gen_mult_seq : LATENCY = 4 ----------------------------------------------
set mcp_mul_from [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ *mcp_mul_op?_q_reg*}]
set mcp_mul_to   [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ *mcp_mul_res_q_reg*}]
set_multicycle_path -setup 4 -from $mcp_mul_from -to $mcp_mul_to
set_multicycle_path -hold  3 -from $mcp_mul_from -to $mcp_mul_to

# ---- gen_div_seq : LATENCY = 17 ----------------------------------------------
set mcp_div_from [get_cells -hier -filter {IS_SEQUENTIAL && NAME =~ *mcp_div_op?_q_reg*}]
set mcp_div_to   [get_cells -hier -filter {IS_SEQUENTIAL && (NAME =~ *mcp_div_quo_q_reg* || NAME =~ *mcp_div_rem_q_reg* || NAME =~ *mcp_div_dbz_q_reg*)}]
set_multicycle_path -setup 17 -from $mcp_div_from -to $mcp_div_to
set_multicycle_path -hold  16 -from $mcp_div_from -to $mcp_div_to
