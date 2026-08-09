# Copyright 2019 Xilinx, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Modified by Le Sun, 2026 for the FPGA AES-GCM / experimental MACsec prototype.
# Modifications Copyright (c) 2026 Le Sun.
# Changes: target part set to xcku040-ffva1156-2-e; XF_PROJ_ROOT/CUR_DIR
#          pointed at a local Vitis Libraries checkout. Hardcoded host paths
#          are replaced with <VITIS_SECURITY_LIB_ROOT> for publication.
#
set XPART xcku040-ffva1156-2-e
set CSIM 1
set CSYNTH 1
set COSIM 1
set VIVADO_SYN 0
set VIVADO_IMPL 0
set XF_PROJ_ROOT "<VITIS_SECURITY_LIB_ROOT>"
set CUR_DIR "<VITIS_SECURITY_LIB_ROOT>/L1/tests/gcm/aes128enc"
