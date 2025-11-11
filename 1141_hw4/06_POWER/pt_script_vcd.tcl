#PrimeTime Script
set power_enable_analysis TRUE
set power_analysis_mode time_based

read_file -format verilog  ../02_SYN/Netlist/IOTDF_syn.v
current_design IOTDF
link

read_sdf -load_delay net ../02_SYN/Netlist/IOTDF_syn.sdf


## Measure  power
#report_switching_activity -list_not_annotated -show_pin

read_vcd  -strip_path test/u_IOTDF  ../03_GATE/IOTDF_F1.vcd
update_power
report_power 
report_power > F1_4.vcd.power

read_vcd  -strip_path test/u_IOTDF  ../03_GATE/IOTDF_F2.vcd
update_power
report_power
report_power >> F1_4.vcd.power

read_vcd  -strip_path test/u_IOTDF  ../03_GATE/IOTDF_F3.vcd
update_power
report_power
report_power >> F1_4.vcd.power

read_vcd  -strip_path test/u_IOTDF  ../03_GATE/IOTDF_F4.vcd
update_power
report_power
report_power >> F1_4.vcd.power



