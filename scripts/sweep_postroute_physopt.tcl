# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Le Sun
# Author: Le Sun
#
# Part of the FPGA AES-GCM / MACsec research prototype.
#
set proj "<archived-project-root>/mqnic_gcm_codex.xpr"
set base_dcp "<archived-project-root>/mqnic_gcm_codex.runs/impl_1/fpga_routed.dcp"
set outdir "<archived-project-root>"

proc run_case {name cmd} {
  global base_dcp outdir
  puts "=== CASE $name BEGIN ==="
  open_checkpoint $base_dcp
  eval $cmd
  set rpt "$outdir/sweep_${name}.rpt"
  report_timing_summary -file $rpt
  set dcp "$outdir/sweep_${name}.dcp"
  write_checkpoint -force $dcp
  close_design
  puts "=== CASE $name END ==="
}

open_project $proj

run_case default_physopt {phys_opt_design}
run_case explore {phys_opt_design -directive Explore}
run_case agg_explore {phys_opt_design -directive AggressiveExplore}
run_case alt_repl {phys_opt_design -directive AlternateReplication}
run_case agg_fanout {phys_opt_design -directive AggressiveFanoutOpt}
run_case holdfix {phys_opt_design -directive ExploreWithHoldFix}
run_case agholdfix {phys_opt_design -directive ExploreWithAggressiveHoldFix}
run_case add_retime {phys_opt_design -directive AddRetime}
run_case altflow_retime {phys_opt_design -directive AlternateFlowWithRetiming}
run_case runtime_opt {phys_opt_design -directive RuntimeOptimized}

# Option-based experiments (no -directive)
run_case clock_opt {phys_opt_design -clock_opt}
run_case route_place_rewire {phys_opt_design -routing_opt -placement_opt -rewire -critical_cell_opt}

close_project
exit
