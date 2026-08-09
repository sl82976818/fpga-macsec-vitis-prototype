# SPDX-License-Identifier: BSD-2-Clause
#
# Copyright (c) 2026 Le Sun
# Author: Le Sun
#
# Part of the FPGA AES-GCM / MACsec research prototype.
#
open_project <archived-project-root>/mqnic_gcm_codex.xpr

# 1) Clean rerun: synthesis + implementation to route_design
reset_run synth_1
reset_run impl_1

launch_runs synth_1 -jobs 16
wait_on_run synth_1

launch_runs impl_1 -to_step route_design -jobs 16
wait_on_run impl_1

# 2) Post-route physical optimization (required for near -0.016ns result)
open_run impl_1
phys_opt_design -directive AggressiveExplore

# 3) Save reports/checkpoint in project root for easy access
report_timing_summary -file <archived-project-root>/result_timing_postroute_physopt.rpt
report_timing_summary -max_paths 20 -path_type summary -file <archived-project-root>/result_timing_postroute_physopt_top20.rpt
write_checkpoint -force <archived-project-root>/result_postroute_physopt.dcp

# Optional: utilization snapshot
report_utilization -file <archived-project-root>/result_util_postroute_physopt.rpt
